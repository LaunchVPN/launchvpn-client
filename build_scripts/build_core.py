#!/usr/bin/env python3
"""Builds the native core and Geodata only, for CI jobs that build the App themselves."""

import argparse
import os

from app.builder import Builder


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("system", choices=("android", "ios"))
    args = parser.parse_args()
    Builder("OneXray", args.system, os.path.dirname(os.path.abspath(__file__))).build_core()


if __name__ == "__main__":
    main()
