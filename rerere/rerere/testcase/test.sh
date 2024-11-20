#!/bin/dash
swiftc testcase.swift 2>&1 | grep -q 'Undefined symbols for architecture arm64:'
