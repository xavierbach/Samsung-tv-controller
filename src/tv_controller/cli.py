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
        extras = ", ".join(x for x in (tv.model, tv.mac) if x)
        print(f"  {tv.friendly_name}  ({tv.host}{', ' + extras if extras else ''})")
        if args.save:
            name = tv.friendly_name.lower().replace(" ", "-")
            config.add(TVConfig(name=name, host=tv.host, mac=tv.mac))
    if args.save:
        config.save()
        missing = [tv.friendly_name for tv in found if not tv.mac]
        print(f"\nSaved {len(found)} TV(s) to config, with wake-on-LAN MACs where "
              "the TV reported one.")
        if missing:
            print("No MAC reported by: " + ", ".join(missing) + " — add those to "
                  "the config file by hand for reliable power on.")
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
        atv = f"  [appletv: {tv.cfg.apple_tv}]" if tv.cfg.apple_tv else ""
        print(f"  {s['name']:<20} {s['host']:<16} {s['power']}{atv}")
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


def cmd_serve(args: argparse.Namespace) -> int:
    from .server import serve

    serve(host=args.host, port=args.port)
    return 0


def cmd_atv_scan(args: argparse.Namespace) -> int:
    from . import appletv

    print("Scanning for Apple TVs...")
    for atv in appletv.scan():
        print(f"  {atv['name']:<24} {atv['host']:<16} {atv['model']}")
    return 0


def cmd_atv_pair(args: argparse.Namespace) -> int:
    from . import appletv

    config = Config.load()
    if args.tv_name not in config.tvs:
        print(f"Unknown TV '{args.tv_name}' — run 'tvctl list' to see names.")
        return 1
    appletv.pair(args.host)
    config.tvs[args.tv_name].apple_tv = args.host
    config.save()
    print(f"Apple TV at {args.host} is now linked to '{args.tv_name}'.")
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

    p = sub.add_parser("serve", help="run the home server (for the apps & HomePods)")
    p.add_argument("--host", default="0.0.0.0")
    p.add_argument("--port", type=int, default=8765)
    p.set_defaults(func=cmd_serve)

    p = sub.add_parser("atv-scan", help="find Apple TVs on the network")
    p.set_defaults(func=cmd_atv_scan)

    p = sub.add_parser("atv-pair", help="pair an Apple TV and link it to a TV")
    p.add_argument("tv_name", help="which Samsung TV this Apple TV is plugged into")
    p.add_argument("host", help="Apple TV IP address (from atv-scan)")
    p.set_defaults(func=cmd_atv_pair)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
