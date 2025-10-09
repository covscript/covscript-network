#!/bin/bash
CURRENT_FOLDER=$(dirname $(readlink -f "$0"))
cd $CURRENT_FOLDER
ecs -f -o . ../netutils.ecs &
ecs -f -o . ./argparse.ecs &
ecs -f -o . ./simple_tls.ecs &
wait
