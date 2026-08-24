#!/bin/bash
docker run --rm -it \
  -v $(pwd):/workspace \
  -w /workspace \
  openroad/orfs bash
