"""Check that the Anthropic API key in the environment is accepted.

    python3 server/check_key.py

It shows what the server received (masked, so it is safe to read out) and then asks
Anthropic to list one model, which is free and needs a valid key. Exit status: 0 accepted,
1 rejected, 2 not set up, 3 could not reach Anthropic.
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import photo  # noqa: E402


def main():
    anthropic = photo._load_sdk()
    if anthropic is None:
        print("The anthropic package isn't installed. See 'Photo import' in the README.")
        return 2
    raw = os.environ.get("ANTHROPIC_API_KEY")
    key = photo.api_key()
    if not key:
        print("ANTHROPIC_API_KEY is not set in this environment.")
        return 2

    print(f"Key received: {photo.mask_key(key)}  ({len(key)} characters)")
    if raw != key:
        print("  (I removed spaces, quotes or a prefix that came along with it.)")
    for problem in photo.key_problems(key):
        print(f"  Looks wrong: {problem}.")

    try:
        anthropic.Anthropic(api_key=key, timeout=20.0).models.list(limit=1)
    except anthropic.AuthenticationError:
        print("REJECTED: Anthropic says this key is not valid (401).")
        print("  Compare the last four characters above with the key in console.anthropic.com > API keys.")
        print("  Common causes: the key was copied incompletely, it was revoked or deleted, or it is not an")
        print("  API key (a Claude.ai or Claude Code login is not one). Create a fresh key and try again.")
        return 1
    except anthropic.PermissionDeniedError:
        print("The key is valid but is not allowed to do this (403). Check its workspace and permissions.")
        return 1
    except anthropic.APIConnectionError:
        print("Couldn't reach api.anthropic.com. Check the internet connection (and any VPN).")
        return 3
    except anthropic.APIStatusError as e:
        print(f"Anthropic returned status {e.status_code}: {e.message}")
        return 3
    print("ACCEPTED: Anthropic accepts this key.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
