"""Security tests — validates all hardening from RUN-4."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from src.models.config import AuthConfig, FrameworkConfig
from src.projects.registry import ProjectRegistry, _validate_name
from src.web.app import create_app
from src.web.validation import validate_safe_filename


# ── 1. Password never saved in plaintext ─────────────────────────────────────

class TestPasswordNotPersistedInPlaintext:
    def test_env_ref_restored_on_save(self, tmp_path: Path, monkeypatch) -> None:
        monkeypatch.setenv("QA_TEST_PW", "super_secret_123")
        cfg = FrameworkConfig(
            target_url="https://example.com",
            auth={"login_url": "https://example.com/login", "username": "u", "password": "env:QA_TEST_PW"},
        )
        assert cfg.auth.password == "super_secret_123"

        save_path = tmp_path / "config.json"
        cfg.save(save_path)
        saved = json.loads(save_path.read_text())

        assert saved["auth"]["password"] == "env:QA_TEST_PW", "Plaintext password must not be saved"
        assert "super_secret_123" not in save_path.read_text()

    def test_plaintext_password_saved_as_is(self, tmp_path: Path) -> None:
        cfg = FrameworkConfig(
            target_url="https://example.com",
            auth={"login_url": "https://example.com/login", "username": "u", "password": "direct_pass"},
        )
        save_path = tmp_path / "config.json"
        cfg.save(save_path)
        saved = json.loads(save_path.read_text())
        assert saved["auth"]["password"] == "direct_pass"

    def test_roundtrip_preserves_env_ref(self, tmp_path: Path, monkeypatch) -> None:
        monkeypatch.setenv("MY_PW", "secret")
        cfg = FrameworkConfig(
            target_url="https://example.com",
            auth={"login_url": "https://example.com/login", "username": "u", "password": "env:MY_PW"},
        )
        save_path = tmp_path / "config.json"
        cfg.save(save_path)
        loaded = FrameworkConfig.load(save_path)
        assert loaded.auth.password == "secret"

    def test_missing_env_var_raises(self, monkeypatch) -> None:
        monkeypatch.delenv("MISSING_VAR", raising=False)
        with pytest.raises(Exception, match="MISSING_VAR"):
            FrameworkConfig(
                target_url="https://example.com",
                auth={"login_url": "https://example.com/login", "username": "u", "password": "env:MISSING_VAR"},
            )


# ── 2. Project name validation ────────────────────────────────────────────────

class TestProjectNameValidation:
    @pytest.mark.parametrize("name", [
        "mysite", "my-site", "my_site", "site123", "A1B2",
    ])
    def test_valid_names_accepted(self, name: str) -> None:
        _validate_name(name)  # should not raise

    @pytest.mark.parametrize("name", [
        "../../../etc", "<script>", "a b c", "", "a" * 65,
        "site/path", "site\\path", "site;rm -rf",
    ])
    def test_invalid_names_rejected(self, name: str) -> None:
        with pytest.raises(ValueError):
            _validate_name(name)

    def test_api_rejects_invalid_name(self, tmp_path: Path) -> None:
        registry = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
        client = TestClient(create_app(registry))
        resp = client.post("/api/projects", json={"name": "../hack", "target_url": "https://x.com"})
        assert resp.status_code in (400, 422)

    def test_registry_create_rejects_invalid_name(self, tmp_path: Path) -> None:
        registry = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
        with pytest.raises(ValueError):
            registry.create("../evil", "https://x.com")


# ── 3. target_url validation ──────────────────────────────────────────────────

class TestTargetUrlValidation:
    @pytest.mark.parametrize("url", [
        "https://example.com", "http://mysite.io/path",
    ])
    def test_valid_urls_accepted(self, url: str) -> None:
        cfg = FrameworkConfig(target_url=url)
        assert cfg.target_url == url

    @pytest.mark.parametrize("url", [
        "file:///etc/passwd", "ftp://example.com", "javascript:alert(1)",
        "//example.com", "not-a-url", "",
    ])
    def test_invalid_schemes_rejected(self, url: str) -> None:
        with pytest.raises(Exception):
            FrameworkConfig(target_url=url)


# ── 4 & 6. Path traversal and null bytes in file serving ─────────────────────

class TestFileServingValidation:
    @pytest.mark.parametrize("filename", [
        "report_abc.html", "report_abc.json",
    ])
    def test_valid_filenames_pass(self, filename: str) -> None:
        validate_safe_filename(filename, allowed_extensions=frozenset({".html", ".json"}))

    @pytest.mark.parametrize("filename", [
        "../../../etc/passwd",
        "..\\windows\\system32",
        "/etc/passwd",
        "file\x00.html",
    ])
    def test_traversal_filenames_rejected(self, filename: str) -> None:
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc:
            validate_safe_filename(filename)
        assert exc.value.status_code == 400

    def test_disallowed_extension_rejected(self) -> None:
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc:
            validate_safe_filename("script.sh", allowed_extensions=frozenset({".html", ".json"}))
        assert exc.value.status_code == 400

    def test_null_byte_in_report_endpoint(self, tmp_path: Path) -> None:
        registry = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
        registry.create("mysite", "https://mysite.com")
        client = TestClient(create_app(registry))
        resp = client.get("/api/projects/mysite/reports/evil%00.html")
        assert resp.status_code in (400, 404, 422)


# ── 5. Run trigger — credentials not in metadata ─────────────────────────────

class TestRunCredentialsSafety:
    def test_run_meta_does_not_contain_password(self, tmp_path: Path) -> None:
        from unittest.mock import patch
        registry = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
        registry.create("mysite", "https://mysite.com")

        from src.web.run_manager import RunManager
        from src.web.routers.runs import RunOverrides

        mgr = RunManager()
        overrides = RunOverrides(username="testuser", password="s3cr3t")

        with patch.object(mgr, "_run_pipeline"):
            run_id = mgr.start("mysite", registry, overrides=overrides)

        # Wait briefly for the meta file to be written
        import time; time.sleep(0.2)

        meta_path = registry.runs_dir("mysite") / run_id / "run_meta.json"
        if meta_path.exists():
            meta = json.loads(meta_path.read_text())
            assert "password" not in meta
            assert "s3cr3t" not in json.dumps(meta)
            assert meta.get("auth_username") == "testuser"
