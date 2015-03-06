#!/bin/bash -

find scripts -type f -not -name '*.awk' -print0 | xargs -0 grep -HL '^#!/usr/bin/env python' | xargs bashate -v

