#!/bin/bash

./retrieve_logs.sh jetson_log.txt && cat jetson_log.txt | grep -E "d4xx|max9295|max9296" | tee jetson_log.txt && vim jetson_log.txt
