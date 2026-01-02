---
id: task-002
title: Search Enhancement - Search by Field
status: In Progress
assignee:
  - Tardoe
created_date: '2026-01-01 06:28'
updated_date: '2026-01-01 07:02'
labels: []
dependencies: []
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
This feature aims to improve the search functionality allowing a user to search by field for a given model or associated
model.

We should create a modular component that can be applied to both index pages and on top of tables that are part of other
pages.

When a user goes to search, they should be able to specify search criterial with the format <field>:<term> where the
field is the field name of the model being shown in the table. The field names should be auto-filled, allowing a user to
see what fields are available. The search term can be either exact or partial. The user should be able to specify
multiple pairs of field and term. If a field isn't provided, the search term should apply across all fields of the model
in question.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 User can search using field:value syntax (e.g., manufacturer:Boeing)
- [ ] #2 User can use * suffix for partial matching (e.g., manufacturer:Boe*)
- [ ] #3 User can use quoted values for exact phrases (e.g., operator:"Qantas Airways")
- [ ] #4 User can negate searches with - prefix or NOT keyword
- [ ] #5 User can combine criteria with AND/OR boolean operators
- [ ] #6 Unqualified search terms fall back to full-text search across all fields
- [ ] #7 Field names auto-complete as user types (minimum 2 characters)
- [ ] #8 Field values auto-complete after typing field: (from Meilisearch facets)
- [ ] #9 Parsed search tokens display as removable chips/tags
- [ ] #10 Clicking X on a chip removes that filter and updates results
- [ ] #11 Search component is reusable across all index pages
- [ ] #12 Search works with existing infinite scroll pagination
- [ ] #13 Associated model fields are searchable (e.g., manufacturer on Aircraft)
- [ ] #14 Search preserves existing Turbo Stream response format
- [ ] #15 Unit tests cover query parser with all syntax variations
- [ ] #16 System tests verify autocomplete and chip UI interactions

<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->

## Implementation Plan

### Query Syntax

- `field:value` - Exact match on field
- `field:value*` - Partial match (prefix) on field
- `field:"exact phrase"` - Exact match with spaces
- `-field:value` or `NOT field:value` - Negation
- `field:a AND field:b` - Boolean AND (default between pairs)
- `field:a OR field:b` - Boolean OR
- Unqualified text falls back to full-text search across all fields

### Architecture

```
app/services/search/
  query_parser.rb           # Parse raw query -> tokens
  query_translator.rb       # Tokens -> Meilisearch params
  field_registry.rb         # Model -> searchable fields mapping
  autocomplete_service.rb   # Field & value suggestions

app/controllers/concerns/
  field_searchable.rb       # Shared search logic

app/controllers/
  search_suggestions_controller.rb  # Autocomplete API

app/javascript/controllers/
  field_search_controller.js        # Main orchestrator
  search_chip_controller.js         # Chip removal

app/views/shared/search/
  _field_search_form.html.erb       # Reusable component
  _search_chip.html.erb             # Token chip
```

### Implementation Phases

**Phase 1: Core Backend**

- Create `Search::QueryParser` - tokenise query string
- Create `Search::SearchToken` - token data structure
- Create `Search::QueryTranslator` - convert to Meilisearch params
- Create `Search::FieldRegistry` - define searchable fields per model

**Phase 2: Model Updates**

- Add `filterable_attributes` to Aircraft model (and verify others)
- Run `rails meilisearch:reindex` for affected models

**Phase 3: Controller Integration**

- Create `FieldSearchable` concern with `field_search(model, query)` method
- Create `SearchSuggestionsController` for autocomplete API
- Update `AircraftController` as pilot implementation
- Add route: `GET /search/suggestions`

**Phase 4: Frontend**

- Create `field_search_controller.js` - autocomplete, chip management
- Create `search_chip_controller.js` - chip removal
- Create view partials for reusable search component
- Update Aircraft index view

**Phase 5: Rollout**

- Apply to remaining controllers: AircraftTypes, Operators, Airports, Manufacturers, Countries, Routes, Runways

**Phase 6: Testing**

- Unit tests for parser, translator, registry
- Controller tests for suggestions endpoint
- System tests for UI interactions

### Technical Notes

1. **No external gems needed** - Custom lightweight parser sufficient for this syntax
2. **Partial matching** - Uses `*` suffix with Meilisearch `attributesToSearchOn` parameter
3. **Flattened associations** - Aircraft already indexes manufacturer/operator names
4. **Dynamic autocomplete** - Field names from FieldRegistry, values from Meilisearch facets

<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->

## Implementation Progress (Phase 1-4 Complete)

### Files Created

**Backend Services:**

- `app/services/search/search_token.rb` - Token data structure
- `app/services/search/query_parser.rb` - Query string tokenisation
- `app/services/search/field_registry.rb` - Model field mappings
- `app/services/search/query_translator.rb` - Meilisearch parameter translation
- `app/services/search/autocomplete_service.rb` - Field/value suggestions

**Controllers:**

- `app/controllers/concerns/field_searchable.rb` - Reusable search concern
- `app/controllers/search_suggestions_controller.rb` - Autocomplete API

**Frontend:**

- `app/javascript/controllers/field_search_controller.js` - Stimulus controller
- `app/views/shared/search/_field_search_form.html.erb` - Search form partial
- `app/views/shared/search/_search_chip.html.erb` - Chip display partial

**Tests:**

- `test/services/search/query_parser_test.rb`
- `test/services/search/query_translator_test.rb`
- `test/services/search/field_registry_test.rb`

### Files Modified

- `app/models/aircraft.rb` - Added `filterable_attributes`
- `app/controllers/aircraft_controller.rb` - Uses `FieldSearchable` concern
- `app/views/aircraft/index.html.erb` - Uses new search component
- `config/routes.rb` - Added `/search/suggestions` route

### Next Steps

1. **Reindex Aircraft:** Run `rails meilisearch:reindex CLASS=Aircraft`
2. **Test in browser:** Verify autocomplete and search work
3. **Fix test infrastructure:** Rails 8.1 minitest compatibility issue
4. **Rollout to other controllers:** Apply pattern to remaining index pages

### Known Issues

- Test runner not executing tests (pre-existing Rails 8.1/minitest issue)

<!-- SECTION:NOTES:END -->
