# workbench
## docker/podman support inside container
You are able to use podman/docker inside the container by passing the outer docker socket through to the container: ˋdocker run --rm -it --privileged -v /var/run/docker.sock:/var/run/docker.sock lallinger/workbench:latestˋ

Using podman this leads to a warning. Also it doesn't work if the image is not yet on disk and needs downloading, just rerun the command and it works.

## Use outside of docker
The ˋsetup.shˋ script is idempotent for a single timestamp. If you want to update the installed software you can easily rerun it.
