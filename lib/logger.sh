#!/bin/sh

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

info() {
    echo "${GREEN}[INFO]${RESET} $1"
}

warn() {
    echo "${YELLOW}[WARN]${RESET} $1"
}

error() {
    echo "${RED}[ERROR]${RESET} $1"
}
