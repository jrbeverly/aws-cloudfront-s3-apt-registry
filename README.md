# CloudFront S3 APT Registry

> [!WARNING]
> **AI-authored:** This change was autonomously planned and implemented by an AI software factory from a human-authored specification, with possible subsequent human review or modification.

Tests whether a static APT repository in a private S3 bucket can be served through CloudFront with viewer mTLS, so `apt install` works only with a client certificate and the bucket cannot be read directly.

```sh
scripts/bootstrap-ca.sh
terraform init && terraform apply
scripts/publish.sh
docker/run-validation.sh
aws s3 rm "s3://$(terraform output -raw bucket_name)" --recursive && terraform destroy
```

Yielding:

```text
Ign:1 https://d1mplq92pn85xd.cloudfront.net stable InRelease
Get:2 https://d1mplq92pn85xd.cloudfront.net stable Release [347 B]
Ign:3 https://d1mplq92pn85xd.cloudfront.net stable Release.gpg
Get:4 https://d1mplq92pn85xd.cloudfront.net stable/main amd64 Packages [327 B]
Fetched 674 B in 1s (845 B/s)
Reading package lists...
Reading package lists...
Building dependency tree...
Reading state information...
The following NEW packages will be installed:
  hello-lab
0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.
Need to get 820 B of archives.
After this operation, 0 B of additional disk space will be used.
Get:1 https://d1mplq92pn85xd.cloudfront.net stable/main amd64 hello-lab amd64 1.0.0 [820 B]
debconf: delaying package configuration, since apt-utils is not installed
Fetched 820 B in 0s (5095 B/s)
Selecting previously unselected package hello-lab.
(Reading database ... 4946 files and directories currently installed.)
Preparing to unpack .../hello-lab_1.0.0_amd64.deb ...
Unpacking hello-lab (1.0.0) ...
Setting up hello-lab (1.0.0) ...
installed from a static S3 repository
```

## Notes

- Straightforward experiment, little unexpected
- Confirms original assumption that certificate-driven access flow works for an APT mirror
- Potentially useful as lightweight external mirror
- Potentially useful for self-hosted package distribution
- Potentially useful for internal package repositories
- Useful anywhere controlled package access needs to remain simple
- Particularly relevant for Packer build flows
- Enables packages / tools to be pulled during machine-image construction
- Supports pre-baking required tooling directly into machine images
- Could provide controlled package source for repeatable image builds
