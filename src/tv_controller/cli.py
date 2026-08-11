"""Command-line interface: discover TVs, register them, and talk to them."""

from __future__ import annotations

import argparse
import sys

from .config import Config, TVConfig
from .tv import TVManager


def cmd_discover(args: argparse.Namespace) -> int:
    from .discovery import discover

    print("Scanning the network for Samsung TVs...")
    found = discover(timeout=args.timeout)
    if not found:
        print("No Samsung TVs found. Make sure they're on the same network and awake.")
        return 1

    config = Config.load()
    for tv in found:
        print(f"  {tv.friendly_name}  ({tv.host}{', ' + tv.model if tv.model else ''})")
        if args.save:
            name = tv.friendly_name.lower().replace(" ", "-")
            config.add(TVConfig(name=name, host=tv.host))
    if args.save:
        config.save()
        print(f"\nSaved {len(found)} TV(s) to config. Add each TV's MAC address to the "
              "config file to enable wake-on-LAN power on.")
    else:
        print("\nRe-run with --save to add these TVs to your config.")
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    config = Config.load()
    config.add(TVConfig(name=args.name, host=args.host, mac=args.mac, port=args.port))
    config.save()
    print(f"Added '{args.name}' ({args.host}).")
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    manager = TVManager()
    if not manager.tvs:
        print("No TVs configured. Run 'tvctl discover --save' or 'tvctl add'.")
        return 1
    for tv in manager.tvs.values():
        s = tv.status()
        print(f"  {s['name']:<20} {s['host']:<16} {s['power']}")
    return 0


def cmd_do(args: argparse.Namespace) -> int:
    from .agent import TVAgent

    agent = TVAgent()
    print(agent.ask(" ".join(args.request)))
    return 0


def cmd_chat(args: argparse.Namespace) -> int:
    from .agent import TVAgent

    agent = TVAgent()
    print("Samsung TV super controller — tell me what to do ('quit' to exit).")
    while True:
        try:
            line = input("you> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not line:
            continue
        if line.lower() in ("quit", "exit", "q"):
            break
        try:
            print(agent.ask(line))
        except Exception as exc:
            print(f"error: {exc}", file=sys.stderr)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="tvctl",
        description="Control every Samsung TV in your house with natural language.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("discover", help="scan the network for Samsung TVs")
    p.add_argument("--save", action="store_true", help="add found TVs to the config")
    p.add_argument("--timeout", type=float, default=3.0)
    p.set_defaults(func=cmd_discover)

    p = sub.add_parser("add", help="manually add a TV")
    p.add_argument("name")
    p.add_argument("host")
    p.add_argument("--mac", help="MAC address, enables wake-on-LAN power on")
    p.add_argument("--port", type=int, default=8002)
    p.set_defaults(func=cmd_add)

    p = sub.add_parser("list", help="list configured TVs and their power state")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("do", help='run one command, e.g.: tvctl do "mute the bedroom tv"')
    p.add_argument("request", nargs="+")
    p.set_defaults(func=cmd_do)

    p = sub.add_parser("chat", help="interactive natural-language session")
    p.set_defaults(func=cmd_chat)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
