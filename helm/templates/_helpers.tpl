{{- define "alura-foods-app.labels"}}
app.kuberntes.io/name: {{.Chart.Name}}
app.kuberntes.io/instance: {{.Release.Name}}
app.kuberntes.io/version: {{.Chart.AppVersion}}
app.kuberntes.io/managed-by: {{.Release.Service}}
{{- end}}
