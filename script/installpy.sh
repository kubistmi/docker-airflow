#!/bin/bash
if [ -e "/reqs/requirements.txt" ]; then
    $(command -v pip) install --user -r /reqs/requirements.txt
fi