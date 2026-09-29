#!/usr/bin/env python3
"""Client-owned model catalogs and global five-agent model configuration.

Discovery only initializes the clients: it never sends a prompt or starts a turn.
Codex uses app-server model/list. Claude uses the SDK's initialize control request.
Protocol references: https://learn.chatgpt.com/docs/app-server and the published
@anthropic-ai/claude-agent-sdk SDKControlInitializeResponse / ModelInfo types.
"""

import argparse
import contextlib
import json
import os
from pathlib import Path
import queue
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time

try:
    import tomllib
except ImportError:
    sys.exit("Model selection requires Python 3.11 or newer.")

ROLES = ("chief", "scout", "builder", "verifier", "operator")
GUIDANCE = ("strong reasoning model recommended", "lighter / fast model recommended",
            "strong coding model recommended", "strong reasoning model recommended",
            "lighter / fast model recommended")


def read(path):
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError(f"Expected a regular file: {path}")
    return path.read_text() if path.exists() else ""


def json_text(value):
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".five-agent-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        if path.exists():
            os.chmod(name, path.stat().st_mode & 0o777)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


class Client:
    def __init__(self, command, env, cwd):
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                        text=True, env=env, cwd=cwd, start_new_session=True)
        self.messages = queue.Queue()
        self.deadline = time.monotonic() + 45
        threading.Thread(target=self.collect, daemon=True).start()

    def collect(self):
        try:
            for line in self.process.stdout:
                try:
                    self.messages.put(json.loads(line))
                except ValueError:
                    continue
        finally:
            self.messages.put(None)

    def send(self, value):
        self.process.stdin.write(json.dumps(value) + "\n")
        self.process.stdin.flush()

    def receive(self, predicate):
        while True:
            remaining = self.deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError("Model discovery timed out. Check your client login and connection.")
            try:
                message = self.messages.get(timeout=remaining)
            except queue.Empty:
                raise ValueError("Model discovery timed out. Check your client login and connection.") from None
            if message is None:
                raise ValueError("Client closed before returning models. Check its installation and login.")
            if isinstance(message, dict) and predicate(message):
                return message

    def rpc(self, number, method, params):
        self.send({"id": number, "method": method, "params": params})
        response = self.receive(lambda message: message.get("id") == number)
        if "error" in response:
            raise ValueError(f"Client rejected {method}; update the client and retry.")
        return response["result"]

    def close(self):
        with contextlib.suppress(ProcessLookupError):
            os.killpg(self.process.pid, signal.SIGTERM)
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait()
        self.process.stdin.close()
        self.process.stdout.close()


def discover(target, home):
    env = os.environ.copy()
    # Set the child's client root; never change the installer's own environment.
    env["CODEX_HOME" if target == "codex" else "CLAUDE_CONFIG_DIR"] = str(home)
    env.pop("CLAUDECODE", None)
    command = (["codex", "app-server"] if target == "codex" else
               ["claude", "--print", "--input-format", "stream-json",
                "--output-format", "stream-json", "--verbose", "--no-session-persistence",
                "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}'])
    # A neutral working directory avoids project-local model/settings overrides.
    with tempfile.TemporaryDirectory(prefix="five-agent-catalog-") as cwd:
        client = Client(command, env, cwd)
        try:
            if target == "codex":
                client.rpc(0, "initialize", {"clientInfo": {"name": "five_agent_build",
                           "title": "five-agent-build installer", "version": "1.0"}})
                client.send({"method": "initialized", "params": {}})
                entries, cursor, seen = [], None, set()
                while True:
                    page = client.rpc(len(seen) + 1, "model/list",
                                      {"limit": 100, "includeHidden": False, "cursor": cursor})
                    entries.extend(page["data"])
                    cursor = page.get("nextCursor")
                    if not cursor:
                        break
                    if cursor in seen:
                        raise ValueError("Client returned a repeated model-list cursor.")
                    seen.add(cursor)
                catalog = [{"id": item["model"], "label": item.get("displayName", item["model"]),
                            "effort": item.get("defaultReasoningEffort")}
                           for item in entries if not item.get("hidden", False)]
            else:
                client.send({"type": "control_request", "request_id": "models",
                             "request": {"subtype": "initialize"}})
                result = client.receive(lambda message: message.get("type") == "control_response"
                                        and message.get("response", {}).get("request_id") == "models")
                response = result["response"]
                if response.get("subtype") != "success":
                    raise ValueError("Claude rejected model discovery. Update Claude Code and retry.")
                catalog = [{"id": item["value"], "label": item.get("displayName", item["value"])}
                           for item in response["response"]["models"]]
        finally:
            client.close()
    unique = {}
    for item in catalog:
        if not isinstance(item["id"], str) or not item["id"] or any(ord(c) < 32 for c in item["id"]):
            raise ValueError("Client returned an invalid model identifier.")
        unique.setdefault(item["id"], item)
    if not unique:
        raise ValueError("Client returned no available models. Check your login and retry.")
    return list(unique.values())


def change_toml_model(text, model, key="model"):
    """Patch one root scalar while verifying every unrelated parsed value survives."""
    original = tomllib.loads(text)
    wanted = dict(original)
    wanted[key] = model
    replacement = key + " = " + json.dumps(model)
    escaped = re.escape(key)
    pattern = rf'''(?m)^[ \t]*(?:{escaped}|"{escaped}"|'{escaped}')[ \t]*=[^\n]*'''
    candidates = [replacement + "\n" + text] if key not in original else [
        text[:match.start()] + replacement + text[match.end():]
        for match in re.finditer(pattern, text)]
    for candidate in candidates:
        try:
            if tomllib.loads(candidate) == wanted:
                return candidate
        except tomllib.TOMLDecodeError:
            continue
    raise ValueError("Cannot safely update the main model in config.toml; simplify its model entry first.")


class Installation:
    def __init__(self, args):
        self.target = args.target
        self.home = Path(args.home)
        self.repo = Path(args.repo)
        self.templates = self.repo / ("agents" if args.target == "codex" else "claude/agents")
        self.directory = self.home / ".five-agent-build"
        self.generated = self.directory / "agents"
        self.config = self.home / ("config.toml" if args.target == "codex" else "settings.json")
        self.extension = ".toml" if args.target == "codex" else ".md"
        for directory in (self.home, self.directory, self.generated):
            if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
                raise ValueError(f"Expected a regular directory: {directory}")
        self.state = None
        if self.directory.exists():
            if read(self.directory / "source") != str(self.templates) + "\n":
                raise ValueError("Model settings belong to another checkout: " + str(self.directory))
            self.state = json.loads(read(self.directory / "models.json"))

    def current(self):
        text = read(self.config)
        config = tomllib.loads(text) if self.target == "codex" else json.loads(text or "{}")
        if not isinstance(config, dict):
            raise ValueError("Client settings must contain an object.")
        current = {"chief": {"id": config.get("model")}}
        if self.target == "codex" and config.get("model_reasoning_effort"):
            current["chief"]["effort"] = config["model_reasoning_effort"]
        for role in ROLES[1:]:
            if self.state:
                current[role] = self.state[role]
            else:
                text = read(self.templates / (role + self.extension))
                if self.target == "codex":
                    current[role] = {"id": tomllib.loads(text).get("model")}
                else:
                    match = re.search(r"(?m)^model: (.+)$", text.split("---", 2)[1])
                    current[role] = {"id": match.group(1) if match else None}
        return current

    def choose(self):
        current = self.current()
        print(f"\nReading models from {self.target}...", flush=True)
        catalog = discover(self.target, self.home)
        print("\nAvailable models:")
        for number, item in enumerate(catalog, 1):
            label = " ".join(str(item["label"]).split())
            print(f"  {number}) {label} ({item['id']})")
        print("\nEnter keeps the current setting. q cancels. CHIEF sets the global main-session default.")
        chosen = {}
        for role, guidance in zip(ROLES, GUIDANCE):
            previous = current[role]
            while True:
                answer = input(f"{role.upper()} ({guidance}) [{previous['id'] or 'client default'}]: ").strip()
                if answer.lower() == "q":
                    raise ValueError("Cancelled; no model settings changed.")
                if not answer:
                    chosen[role] = previous
                    break
                if answer.isascii() and answer.isdigit() and 1 <= int(answer) <= len(catalog):
                    chosen[role] = catalog[int(answer) - 1]
                    break
                print(f"Choose 1–{len(catalog)}, Enter to keep, or q to cancel.")
        return {"models": chosen, "config_before": read(self.config)}

    def render(self, role, setting):
        text = read(self.templates / (role + self.extension))
        model = setting.get("id")
        if model is None:
            return text
        if self.target == "codex":
            text = change_toml_model(text, model)
            # Use the selected model's advertised default rather than inheriting an
            # unsupported effort from the main session.
            if setting.get("effort"):
                text = re.sub(r'(?m)^model_reasoning_effort = .*\n', '', text)
                text = 'model_reasoning_effort = ' + json.dumps(setting["effort"]) + "\n" + text
            tomllib.loads(text)
            return text
        parts = text.split("---", 2)
        if len(parts) != 3 or parts[0]:
            raise ValueError("Invalid Claude agent frontmatter.")
        header = re.sub(r'(?m)^model: .*\n', '', parts[1])
        return "---" + header + "model: " + json.dumps(model) + "\n---" + parts[2]

    def apply(self, plan):
        models = plan["models"]
        before = read(self.config)
        if before != plan["config_before"]:
            raise ValueError("Client settings changed during selection; rerun the installer.")
        after = before
        if models["chief"].get("id"):
            if self.target == "codex":
                after = change_toml_model(before, models["chief"]["id"])
                if models["chief"].get("effort"):
                    after = change_toml_model(after, models["chief"]["effort"], "model_reasoning_effort")
            else:
                settings = json.loads(before or "{}")
                settings["model"] = models["chief"]["id"]
                after = json_text(settings)
        root = self.home / "agents"
        old_source = self.generated if self.state else self.templates
        linked = root.is_symlink() and os.readlink(root) == str(old_source)
        if root.is_symlink() and not linked:
            raise ValueError("Agents directory belongs to another installation.")
        receipts = self.home / ".five-agent-engineering"
        if receipts.is_symlink():
            raise ValueError("Refusing symlinked receipts directory.")
        writes = {}
        for role in ROLES[1:]:
            name = role + self.extension
            installed = read(root / name)
            expected = read(old_source / name)
            if not installed or installed != expected:
                raise ValueError(f"Installed {role} has changed; reinstall before changing models.")
            if not linked and (read(receipts / (role + ".snapshot")) != installed or
                               read(receipts / (role + ".source")) != str(old_source / name) + "\n"):
                raise ValueError(f"Installed {role} is not owned by this checkout.")
            rendered = self.render(role, models[role])
            writes[self.generated / name] = rendered
            if not linked:
                writes[root / name] = rendered
                writes[receipts / (role + ".snapshot")] = rendered
                writes[receipts / (role + ".source")] = str(self.generated / name) + "\n"
        writes[self.directory / "models.json"] = json_text(models)
        writes[self.directory / "source"] = str(self.templates) + "\n"
        if after != before:
            writes[self.config] = after
        originals = {path: read(path) if path.exists() else None for path in writes}
        # Preserve the original main configuration once, including comments.
        backup = self.directory / "original-config"
        if self.config in writes and not backup.exists():
            read(backup)
            writes[backup] = before
            originals[backup] = None
        previous_link = os.readlink(root) if linked else None
        done = []
        try:
            for path, text in writes.items():
                atomic_write(path, text)
                done.append(path)
            if linked and previous_link != str(self.generated):
                temporary = self.directory / "agents-link"
                if temporary.exists() or temporary.is_symlink():
                    raise ValueError("An unfinished model update exists; remove agents-link and retry.")
                temporary.symlink_to(self.generated)
                os.replace(temporary, root)
            self.state = models
            self.verify()
        except BaseException:
            if linked and os.readlink(root) != previous_link:
                root.unlink()
                root.symlink_to(previous_link)
            for path in reversed(done):
                if originals[path] is None:
                    path.unlink()
                else:
                    atomic_write(path, originals[path])
            for directory in (self.generated, self.directory):
                with contextlib.suppress(OSError):
                    directory.rmdir()
            raise

    def verify(self):
        if self.state is None:
            return
        chief = self.state["chief"]
        current_chief = self.current()["chief"]
        if chief.get("id") and current_chief.get("id") != chief["id"]:
            raise ValueError("CHIEF's global model differs from the saved choice; rerun the installer.")
        if chief.get("effort") and current_chief.get("effort") != chief["effort"]:
            raise ValueError("CHIEF's reasoning setting differs from the saved choice; rerun the installer.")
        for role in ROLES[1:]:
            expected = self.render(role, self.state[role])
            name = role + self.extension
            if read(self.generated / name) != expected or read(self.home / "agents" / name) != expected:
                raise ValueError(f"Model configuration for {role} needs an installer update.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("choose", "apply", "refresh", "verify", "list"))
    parser.add_argument("--target", choices=("codex", "claude"), required=True)
    parser.add_argument("--home", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--plan")
    args = parser.parse_args()
    if args.action == "list":
        print(json_text(discover(args.target, Path(args.home))), end="")
        return
    installation = Installation(args)
    if args.action == "choose":
        atomic_write(Path(args.plan), json_text(installation.choose()))
    elif args.action == "apply":
        installation.apply(json.loads(read(Path(args.plan))))
    elif args.action == "refresh" and installation.state:
        installation.apply({"models": installation.current(), "config_before": read(installation.config)})
    elif args.action == "verify":
        installation.verify()


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, EOFError, KeyboardInterrupt) as error:
        detail = str(error) if not isinstance(error, (EOFError, KeyboardInterrupt)) else "Model selection cancelled."
        sys.exit("ERROR: " + detail)
