# Security policy

Do not open a public issue containing credentials, tokens, private keys, internal
addresses, or unredacted logs. Contact the repository owner privately through the
security reporting channel configured on GitHub.

If a secret is committed: rotate it first, preserve an audit record without the
value, rewrite every affected branch and tag, force-push only after verification,
and notify collaborators to re-clone. Run `tools/dev/scan-secrets.sh` before each
commit. Runtime secret files must remain mode `0600` and outside Git.

Security fixes should include a regression test and supported-version impact.
