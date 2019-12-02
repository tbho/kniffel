#!/bin/sh

release_ctl eval --mfa "Kniffel.DBTasks.migrate/1" --argv -- "$@"
