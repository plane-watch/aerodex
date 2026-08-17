# NATS Enrichment API — Client Reference

Aerodex serves its aviation reference data over NATS request-reply so consumers
can enrich a live ADS-B stream without replicating aerodex's database. This
document is the client-facing contract: the subjects, the request and reply
shapes, and the field semantics.

The API is read-only. There is no subject that mutates aerodex data.

| Subject | Looks up | Key |
|---|---|---|
| `v2.enrich.aircraft` | An aircraft | ICAO 24-bit Mode-S hex |
| `v2.enrich.routes` | A route and its segments | Callsign |
| `v2.enrich.airports` | An airport and its runways | ICAO or IATA code |

The `v2.` prefix is the contract version. Fields may be **added** to a reply
without a version change, so parse permissively and ignore unknown keys. A
removal or a change in meaning will ship under a new prefix.

---

## 1. Making a request

Send a NATS **request** (a publish carrying a reply subject) to the subject, with
a JSON object as the payload. The reply is a JSON object published to the reply
subject.

```
request  v2.enrich.aircraft   {"icao":"7C1469"}
reply                         {"found":true,"aircraft":{ … }}
```

Points that affect how you write a client:

- **A reply is always sent** for a request. A miss, a malformed payload and an
  internal failure each produce a well-formed JSON reply — none of them leave
  you waiting for a timeout. Treat a timeout as a transport or broker problem,
  not as "not found".
- **Still set a request timeout.** It covers broker and network failure, which
  the service cannot reply to. Each request is a single indexed lookup, so the
  server-side cost is small and steady.
- **A plain publish with no reply subject is accepted and produces no reply.**
  There is no fire-and-forget use for this API; if you are not getting a reply,
  check that you are using your client's request method.
- **Requests are load-balanced across replicas** via a queue group, so any given
  request is handled exactly once by one replica. Replies are independent —
  do not assume ordering between concurrent requests.
- **Nothing is cached server-side.** Every request hits the database. If you
  issue the same lookup repeatedly, cache it on your side.
- **Requests in flight during a deployment are completed**, not dropped. A
  rolling restart drains rather than cutting connections.

### Conventions

- Payloads are UTF-8 JSON. The request must be a JSON **object** — an array, a
  bare string or an empty payload is a `bad_request`.
- Reply keys are `snake_case`.
- A successful lookup carries `"found": true` and the entity object. A miss is
  exactly `{"found": false}` with no entity key.
- Lookup keys are matched **case-insensitively**. `"ypph"`, `"YPPH"` and
  `"Ypph"` are the same request.
- Any absent association or column serialises as `null`, never as an omitted key
  or an empty object. Test for `null`, not for key presence.

---

## 2. `v2.enrich.aircraft`

### Request

| Field | Type | Required | Notes |
|---|---|---|---|
| `icao` | string | yes | The 24-bit Mode-S hex, 6 hex digits. Case-insensitive. |
| `include` | array of strings | no | Opt-in extras. `"provenance"` is the only recognised value; unknown values are ignored. |

```json
{ "icao": "7C1469", "include": ["provenance"] }
```

### Reply

```json
{
  "found": true,
  "aircraft": {
    "icao": "7c1469",
    "registration": "VH-VXA",
    "serial_number": "33478",
    "manufacture_year": 2003,
    "registration_date": "2003-11-04",
    "owner": "Qantas Airways Ltd",
    "status": "active",
    "model": "737-838",
    "name": null,
    "engine_count": 2,
    "engine_model": "CFM56-7B26",
    "cabin_configuration": null,
    "type": { "…": "aircraft_type object — §5.3" },
    "operator": { "…": "operator object — §5.2" },
    "registration_country": { "…": "country object — §5.1" }
  }
}
```

| Field | Type | Notes |
|---|---|---|
| `icao` | string | **Lower-cased on output**, whatever case you sent. |
| `registration` | string | The tail number. |
| `serial_number` | string \| null | The manufacturer's serial number (MSN). |
| `manufacture_year` | integer \| null | |
| `registration_date` | string \| null | ISO 8601 date, `YYYY-MM-DD`. |
| `owner` | string \| null | The registered owner, which is not always the operator. |
| `status` | string | One of `active`, `withdrawn`, `hull_loss`, `scrapped`, `stored`, `written_off`. |
| `model` | string \| null | The specific model designation, e.g. `737-838`. |
| `name` | string \| null | The individual aircraft name, where one is recorded. |
| `engine_count` | integer \| null | |
| `engine_model` | string \| null | |
| `cabin_configuration` | string \| null | |
| `type` | object \| null | §5.3 |
| `operator` | object \| null | §5.2 |
| `registration_country` | object \| null | §5.1 |

Note that `model` (on the aircraft) and `type.name` (on the type) are different
things: the former is the individual airframe's designation, the latter the type
it belongs to.

---

## 3. `v2.enrich.routes`

### Request

| Field | Type | Required | Notes |
|---|---|---|---|
| `callsign` | string | yes | The flight callsign, e.g. `QFA123`. Case-insensitive. |

```json
{ "callsign": "QFA123" }
```

`include` is accepted but has no effect on this subject — routes do not carry
field-level provenance, so `"include": ["provenance"]` returns no provenance
block rather than an error.

### Reply

```json
{
  "found": true,
  "route": {
    "callsign": "QFA123",
    "operator": { "…": "operator object — §5.2" },
    "segments": [
      {
        "order": 0,
        "departing_time": "06:00:00",
        "arrival_time": null,
        "airport": { "…": "airport_summary object — §5.5" }
      },
      {
        "order": 1,
        "departing_time": null,
        "arrival_time": "11:35:00",
        "airport": { "…": "airport_summary object — §5.5" }
      }
    ]
  }
}
```

| Field | Type | Notes |
|---|---|---|
| `callsign` | string | As stored, not as sent. |
| `operator` | object \| null | §5.2 |
| `segments` | array | Ordered by `order`, ascending. |
| `segments[].order` | integer | The position in the route. |
| `segments[].departing_time` | string \| null | **Time of day only**, `HH:MM:SS`. |
| `segments[].arrival_time` | string \| null | **Time of day only**, `HH:MM:SS`. |
| `segments[].airport` | object \| null | The lean summary, §5.5 — **no runways**. |

The scheduled times are times of day, not timestamps: there is no date and no
offset. Interpret them against the relevant airport's `timezone`.

Segment airports are the lean summary. For runways, follow up with
`v2.enrich.airports` using the segment's `icao_code`.

---

## 4. `v2.enrich.airports`

### Request

| Field | Type | Required | Notes |
|---|---|---|---|
| `icao` | string | one of the two | The ICAO location indicator, e.g. `YPPH`. |
| `iata` | string | one of the two | The IATA code, e.g. `PER`. |
| `include` | array of strings | no | `"provenance"` supported. |

```json
{ "icao": "YPPH", "include": ["provenance"] }
```

**`icao` takes precedence and there is no fallback.** If you send both and the
`icao` matches nothing, the reply is `{"found": false}` — the `iata` is not then
tried. Send only the code you want matched on.

### Reply

```json
{
  "found": true,
  "airport": {
    "icao_code": "YPPH",
    "iata_code": "PER",
    "wmo_code": "94610",
    "name": "Perth International Airport",
    "city": "Perth",
    "latitude": -31.940278,
    "longitude": 115.966944,
    "altitude": 67.0,
    "timezone": "Australia/Perth",
    "country": { "…": "country object — §5.1" },
    "flight_information_region": { "icao_code": "YBBB", "region": "Brisbane" },
    "runways": [
      {
        "name": "03/21",
        "le_ident": "03",
        "he_ident": "21",
        "heading": 34.0,
        "length": 3444.0,
        "width": 45.0,
        "surface": "ASP",
        "lighted": true,
        "closed": false
      }
    ]
  }
}
```

| Field | Type | Notes |
|---|---|---|
| `icao_code` | string \| null | As stored — **not** case-normalised on output. |
| `iata_code` | string \| null | As stored. |
| `wmo_code` | string \| null | The WMO station identifier, where the airport has one. |
| `name`, `city` | string \| null | |
| `latitude`, `longitude` | number \| null | Decimal degrees, WGS 84. |
| `altitude` | number \| null | The field elevation. **Unit-less** — see below. |
| `timezone` | string \| null | An IANA zone name, e.g. `Australia/Perth`. |
| `country` | object \| null | §5.1 |
| `flight_information_region` | object \| null | §5.4 |
| `runways` | array | Empty when none are recorded. Order is not guaranteed. |

### Runway object

| Field | Type | Notes |
|---|---|---|
| `name` | string \| null | The runway designation, e.g. `03/21`. |
| `le_ident` | string \| null | The low-end identifier. |
| `he_ident` | string \| null | The high-end identifier. |
| `heading` | number \| null | **Unit-less** — see below. |
| `length` | number \| null | **Unit-less** — see below. |
| `width` | number \| null | **Unit-less** — see below. |
| `surface` | string \| null | The source's surface code, e.g. `ASP`, `CON`, `GRS`. Not normalised. |
| `lighted` | boolean | |
| `closed` | boolean | |

**Units are not carried on the wire.** `altitude` and the runway `heading`,
`length` and `width` are emitted as bare numbers because the canonical tables do
not record a unit alongside the value. Do not assume feet or metres from the
magnitude — confirm the convention for the source data feeding your deployment
before doing arithmetic with these fields.

---

## 5. Shared objects

These appear embedded in more than one reply and have the same shape everywhere.
Each serialises to `null` when the association is absent.

### 5.1 `country`

```json
{
  "name": "Australia",
  "iso_2char_code": "AU",
  "iso_3char_code": "AUS",
  "iso_num_code": "036",
  "capital": "Canberra"
}
```

### 5.2 `operator`

```json
{
  "name": "Qantas",
  "icao_code": "QFA",
  "iata_code": "QF",
  "country": { "…": "country object" },
  "parent": { "name": "Qantas Group", "icao_code": null, "iata_code": null }
}
```

`parent` is deliberately shallow — name and codes only, with no nested `parent`
or `country` — so a chain of parent organisations cannot inflate the reply. It
is `null` when the operator has no parent.

### 5.3 `aircraft_type`

```json
{
  "type_code": "B738",
  "name": "737-800",
  "full_name": "Boeing 737-800",
  "category": "airplane",
  "wtc": "M",
  "engines": 2,
  "engine_type": "J",
  "manufacturer": {
    "name": "Boeing",
    "icao_code": "BOEING",
    "alt_names": ["Boeing Commercial Airplanes"],
    "country": { "…": "country object" }
  }
}
```

| Field | Type | Notes |
|---|---|---|
| `type_code` | string \| null | The ICAO type designator. |
| `name` | string \| null | The type name without the manufacturer. |
| `full_name` | string \| null | The manufacturer name prefixed to `name`; falls back to `name` alone when the manufacturer is unknown. |
| `category` | string | One of `airplane`, `helicopter`, `seaplane`, `glider`, `balloon`. |
| `wtc` | string \| null | The wake turbulence category, passed through from the source. |
| `engines` | integer \| null | The engine count for the type. |
| `engine_type` | string \| null | The source's engine type code. Passed through, not normalised. |
| `manufacturer.alt_names` | array of strings | Alternative names. Empty array, never `null`. |

`aircraft.engine_count` describes the individual airframe; `type.engines`
describes the type. They can disagree.

### 5.4 `flight_information_region`

```json
{ "icao_code": "YBBB", "region": "Brisbane" }
```

### 5.5 `airport_summary`

The airport as embedded in a route segment: identical to the full airport object
minus `wmo_code`, `flight_information_region` and `runways`.

```json
{
  "icao_code": "YPPH",
  "iata_code": "PER",
  "name": "Perth International Airport",
  "city": "Perth",
  "latitude": -31.940278,
  "longitude": 115.966944,
  "altitude": 67.0,
  "timezone": "Australia/Perth",
  "country": { "…": "country object" }
}
```

---

## 6. The `provenance` include

Send `"include": ["provenance"]` on `v2.enrich.aircraft` or `v2.enrich.airports`
to add a **top-level** `provenance` block to the reply, reporting where each
tracked field's value came from and how confident aerodex is in it.

```json
{
  "found": true,
  "aircraft": { "…": "as usual" },
  "provenance": {
    "registration": {
      "source_type": "VRSDataAircraftSource",
      "source_id": 123,
      "confidence": 85,
      "combined_at": "2026-01-01T00:00:00Z",
      "source": {
        "name": "Virtual Radar Server Standing Data",
        "url": "https://github.com/vradarserver/standing-data",
        "license": "CC-BY-4.0"
      }
    }
  }
}
```

| Field | Type | Notes |
|---|---|---|
| `source_type` | string | The internal source class name. `AutoGenerated` marks a stub record aerodex created itself. |
| `source_id` | integer \| null | The identifier of the specific source record. |
| `confidence` | integer | The confidence score recorded at merge time; higher is more trusted. |
| `combined_at` | string | An ISO 8601 timestamp of the merge. |
| `source` | object | Human-readable source metadata. **Present only when the source type is in aerodex's registry**, and individual keys are omitted when unknown. |

Three things to know before you rely on this:

1. **The keys are aerodex's internal field names, not the reply's field names.**
   They mostly coincide, but not always — the aircraft reply field `name` is
   tracked as `aircraft_name`. Do not assume you can index the provenance block
   with a key taken from the entity object.
2. **Only tracked fields appear.** The block is not a complete mirror of the
   entity, and it is `{}` for a record with no provenance recorded.
3. **`v2.enrich.routes` has no provenance.** Requesting it there is not an error;
   the block is simply absent.

The block is opt-in because it is comparatively large. Do not request it on a
hot path unless you consume it.

---

## 7. Errors and misses

| Situation | Reply | Client action |
|---|---|---|
| No matching record | `{"found": false}` | A legitimate miss. Cache it if you like; it is not an error. |
| Missing required field; payload empty, not JSON, or not a JSON object | `{"error": "…", "code": "bad_request"}` | A bug in the caller. Do not retry — the same payload always fails. |
| Subject not one of the three | `{"error": "unsupported subject: …", "code": "bad_request"}` | Check the subject spelling. |
| An unexpected server-side failure | `{"error": "internal", "code": "internal"}` | Retrying is reasonable; back off. Aerodex logs the detail. |

Branch on the keys, not on the message text:

- `code` present → an error; its value is `bad_request` or `internal`.
- otherwise `found` is authoritative.

The `error` string on a `bad_request` describes the problem (`"icao is
required"`, `"invalid JSON: …"`) and is safe to log, but it is not a stable
identifier — do not match on it. On an `internal` error, `error` is always the
literal `"internal"`; the cause is deliberately not exposed.

---

## 8. Worked examples

Using the [`nats` CLI](https://github.com/nats-io/natscli):

```bash
# An aircraft, with provenance
nats req v2.enrich.aircraft '{"icao":"7C1469","include":["provenance"]}'

# A route
nats req v2.enrich.routes '{"callsign":"QFA123"}'

# An airport by IATA code
nats req v2.enrich.airports '{"iata":"PER"}'

# A miss
nats req v2.enrich.aircraft '{"icao":"000000"}'
# → {"found":false}

# A malformed request
nats req v2.enrich.aircraft '{}'
# → {"error":"icao is required","code":"bad_request"}
```

---

## 9. Operating the service

Broker URL, queue group, deployment, metrics and shutdown behaviour are covered
in [`nats-enrichment.md`](nats-enrichment.md).
