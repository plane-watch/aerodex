# AERODEX

This is a WIP application/service for managing the Aerodex project.
The aerodex project is an initiative to create a free, open and reliable source of aviation information, such as Aircraft,
Flight Routes, Operators and more.

## Architecture
The application is a Ruby On Rails monolith, using a PostgreSQL database for storage and Meilisearch for search.

External Data Sources are implemented as a `Processor`, which are classes that implement a common interface for fetching and transforming data into the Aerodex schema.


## Getting Started
TODO: Add instructions for getting started


## Backlog
Ref: https://github.com/MrLesk/Backlog.md

Install the `backlog` utility, while in the root of this repo, run `backlog browser` to open the UI.
Install the Claude Code utility / agents similarly following instruction on the github project page.

### Usage
* Each feature, behavoural change or bug should be in it's own task. 
* Humans should (ideally) write the feature spec, or at least guide an agent to produce a feature spec. 
* Issues should (ideally) be reviewed and discussedby humans in the plane.watch #dev-aerodex channel if they require consensus.
* Use larger, more complex models to flesh out an implementation plan and exit/test criteria. 
* Use smaller, cheaper models to implement the plan.
* Use docs (part of backlog) to document novel ideas, concepts etc. 
