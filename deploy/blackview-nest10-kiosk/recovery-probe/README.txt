Blackview NEST 10 Android Recovery signature probe

This package intentionally contains no update binary, updater script, payload,
partition image, kernel, device tree or flashing command. It is expected to
fail after Android Recovery checks its signature.

The package is signed with the public AOSP Android test key. Its only purpose
is to determine whether this NEST 10 Recovery trusts that key.

Expected outcomes:

1. "Signature verification failed" means the key is not trusted.
2. "Installing update..." followed by a missing metadata or update-binary
   error means signature verification succeeded.

This package cannot install an operating system and must never report success.
