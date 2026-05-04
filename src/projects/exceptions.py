class ProjectNotFoundError(Exception):
    def __init__(self, name: str) -> None:
        super().__init__(f"Project '{name}' not found. Run: qa-framework project create --name {name} --target <url>")
        self.name = name


class ProjectAlreadyExistsError(Exception):
    def __init__(self, name: str) -> None:
        super().__init__(f"Project '{name}' already exists. Use: qa-framework project use {name}")
        self.name = name
