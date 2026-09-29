# Helm Shared Files

`zudello-helm-3-dev`: Special branch for `~v3` releases of zudello-helm for v2 clusters.

This should be merged into `main-helm-v3` to go live - it _must not_ be merged into `develop` or `main`.

## To add to a repo

Modify `Chart.yaml` to include:

```
dependencies:
  - name: zudello-helm
    version: "~3"
    repository: "https://zudello.github.io/zudello-helm/"
```

To the `.gitignore` file add:
```
Chart.lock
helm/helmchart/charts/
```

To the Helm chart template, add:
```
{{ template "zudello.standardChecks" . }}
```

Then running the latest `helm-upgrade` will apply the changes to the active cluster, including downloading the required version of the `zudello-helm` chart.

