# Offline packages

Place operator-provided release archives in this directory. Package binaries are
ignored by Git; only this guide and explicitly approved checksum manifests may be
committed.

The resolver searches for an exact compatible local artifact before using the
network. Keep upstream filenames unchanged so operating system, architecture and
version can be matched against each component's `versions.yaml`.

Never place credentials, private keys or secret-bearing configuration here.
