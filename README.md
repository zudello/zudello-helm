# Helm Shared Files

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

# Updating the Helm Chart

When making changes, work in the `develop` branch, be sure to increment the `version` number in `charts/zudello-helm/Chart.yaml`, and then merge to `main` when ready to release. GitHub Actions will then build and make the chart ready to download.

Note most repositories link to the major version only (using `version: ~6` syntax), so it is important to only change the major version number on an API change, and then each repository will need to be updated to the new major version number as needed.