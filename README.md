# swimming-pool-hk-data

Pool data snapshots produced by the [swimming-pool-hk-scraper](https://github.com/huikaihoo/swimming-pool-hk-scraper).

The scraping workflows download the latest Linux release binary and update files under `data/`:

- `Admission` runs the `admission` command and updates admission snapshots.
- `Basic and schedule` runs `basic` followed by `schedule` and updates pool details and schedules.
- `Consolidate data updates` keeps manual commits separate and combines automated data changes into one final data commit.

The two scraping workflows can also be started manually from the Actions tab.

Generated datasets:

- `data/basic/latest.json`
- `data/schedule/latest.json`
- `data/admission/latest.json` and `data/admission/<year>/<YYYY-MM-DD>.json`
