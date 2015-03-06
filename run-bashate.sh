#!/bin/bash -

# We could ignore the E012 bashate rule until the bug will be fixed in it.
find scripts -type f -not -name '*.awk' -print0 | xargs -0 grep -HL '^#!/usr/bin/env python' | xargs bashate -v -i E012

