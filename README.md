# Balena.io BSP layers for Yocto

## Description
This repository enables building balenaOS BSP and related packages for various devices.

## Layers Structure
* meta-balena-bsp-common : layer which contains common recipes for all our supported platforms.
* meta-balena-bsp* : layers which contain recipes specific to yocto versions.
* other files : README, COPYING, etc.

## Dependencies

* http://www.yoctoproject.org/docs/latest/yocto-project-qs/yocto-project-qs.html#packages
* docker
* jq
