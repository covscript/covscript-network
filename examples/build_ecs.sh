#!/bin/bash
CURRENT_FOLDER=$(dirname $(readlink -f "$0"))
cd $CURRENT_FOLDER
ecs -o . ../netutils.ecs &
ecs -o . ./argparse.ecs &
ecs -o . ./simple_tls.ecs &
wait
