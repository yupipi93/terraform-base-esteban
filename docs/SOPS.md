# Sealed secrets

A workspace that sets `sops.enabled: true` gets a Cloud KMS key ring
`<client.name>-<workspace>-sops` with one key, `sops`, in its own project, unless
`sops.kms_key` already names a key. `terraform output sops_kms_key` is the id
that goes in `.sops.yaml`. Start from `.sops.yaml.example`.

```yaml
sops:
  enabled: true
  # kms_key: "projects/<project>/locations/<region>/keyRings/<ring>/cryptoKeys/<key>"
  decrypters:
    - "user:name@example.com"
```

`sops.decrypters` get `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key
the stack creates: they are the people who encrypt and decrypt the files. With
`sops.kms_key` the stack creates no key and grants nothing, so whoever owns that
key grants the role. The created key has `prevent_destroy`, and a key ring can
never be deleted, so turning SOPS off later leaves both in the project.

Put the payload at `secrets/<workspace>/<service>.enc.yaml`. Each top-level key
that matches the `name` of a Cloud Run `secret_env` or `secret_volume` entry of
that service (`DATABASE_PASSWORD`) becomes that secret's version, for the secrets
the stack creates (not `create_secret: false`). A secret with
no entry keeps the placeholder, and Terraform leaves a version added later by
hand alone.

```bash
sops --encrypt --gcp-kms "$(terraform output -raw sops_kms_key)" \
  secrets/pro/api.yaml > secrets/pro/api.enc.yaml
```

The encrypted file is safe to commit. The plaintext yaml is not: delete it after
encrypting, or keep it outside the repository.
