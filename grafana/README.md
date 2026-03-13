# Grafana

## Installation

Simply run the provided script:

```
bash install-grafana.sh
```

The script will create a new namespace called grafana, grant monitoring access and security context to the grafana service account, and then will install the helm chart.

## Usage

Expose the Grafana service, so it can be reached over localhost:

```
oc port-forward -n grafana svc/grafana 3000:80
```

In a web-browser, navigate to [localhost:3000](http://localhost:3000) and login using the credentials:
- Username: admin
- Password: admin

In the top-right corner, click on the "+" symbol, and select `Import Dashboard`. Upload the contents of `dashboard.json` by either dragging and dropping the file into the browser, or by copy-pasting the contents into the text field.

### Note:
I'm using currently `container_cpu_usage_seconds_total` to track pod CPU usage in Grafana, which has an unfortunate side-effect when a cluster is restarted. On restart the value gets reset to 0, so previous data captured is not included against the estimated total cost calculation. So for that one chart in-particular, it will only display the running cost for the cluster for its current run.
