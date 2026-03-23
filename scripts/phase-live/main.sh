#!/usr/bin/env bash

run_phase_live() {
  collect_install_inputs
  summarize_install_plan
  prepare_disk_layout
  bootstrap_base_system
}
