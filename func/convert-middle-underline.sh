#!/bin/bash
# 中划线转换下划线

function convert_middle_underline(){
  local middle=$1
  echo "${middle//-/_}"
}
convert_middle_underline $1
