#update chart.yaml to increment the number 0.1.x
#to create the tgz - helm chart to upload
Set-Location profisee-platform
helm package .

#now upload the in profisee-platform-x.x.x.tgz to github site
#update the index.yaml on github site to have same version number as this
