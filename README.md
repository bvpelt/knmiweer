# knmiweeer
https://editor.swagger.io/
See 
- [1 building simple rust client on youtube](https://www.youtube.com/watch?v=y4UcnudFhM0)
- [building rust client](https://www.youtube.com/watch?v=brX4gzQhYs8)
- [building sdk from openapi spec](https://www.youtube.com/watch?v=uQc9_vBhxYI)

## API Clients
- [postman](https://www.postman.com/)
- [insomnia](https://insomnia.rest/)
- [hoppscotch](https://hoppscotch.io/)

## 1 building simple rust client on youtube

Credentials for youtube: https://console.cloud.google.com/apis/credentials?project=123vrienden


https://www.youtube.com/watch?v=y4UcnudFhM0  39:00

Youtub API https://developers.google.com/youtube/data/reference/rest 

Create credential through https://console.cloud.google.com/apis/credentials

See https://pinguin-01-s-team.postman.co/workspace/My-Workspace~f0ccf46d-5f2e-42f7-82a2-7ce4d9071023/http-request/1046816-5b30091e-89e5-4a06-a433-292c56bc7511?sideView=agentMode 

https://www.phind.com 


## Query

netcdf = "3"          // vereist libnetcdf: `sudo apt install libnetcdf-dev`

```text
// ============================================================
// Gebruik
// ============================================================
// Eerste run (nog geen state):
//   export KNMI_API_KEY=<key>
//   cargo run -- --date 2026-10-01
//
// Vervolgruns (state bestaat, --date wordt genegeerd):
//   cargo run --                  # haalt de volgende 144 bestanden op
//   cargo run -- --max-files 1000 # grotere hap per run
//
// Nieuwe locatie? Reset de sync:
//   rm knmi_state.json temperatuur.csv
//   cargo run -- --date 2026-10-01 --lat 52.030 --lon 5.553
```

## Stations

```text
0 - 20000 - 0 - 06275
│    │      │    └── WMO station number (06275 = Deelen)
│    │      └─────── Organization-local series
│    └────────────── WMO block number (20000 = Netherlands, block 06 series)
└─────────────────── Issuing agency (0 = WMO member)
```

```bash
curl -s -H "Authorization: $KNMI_EDR_API_KEY" \
  "https://api.dataplatform.knmi.nl/edr/v1/collections/10-minute-in-situ-meteorological-observations/locations" \
  | jq '.features[] | select(.id == "0-20000-0-06275")'
```

[api usage](https://developer.dataplatform.knmi.nl/member/)