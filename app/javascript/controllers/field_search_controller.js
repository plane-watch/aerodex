import {Controller} from "@hotwired/stimulus"
import {get} from "@rails/request.js"

/**
 * Orchestrates the field-specific search input with inline chips (tag-input style).
 *
 * This controller handles:
 * - Parsing user input to detect field:value patterns
 * - Fetching autocomplete suggestions for field names and values
 * - Keyboard navigation through suggestions
 * - Managing inline chips within the search bar
 * - Syncing chips with a hidden input for form submission
 */
export default class extends Controller {
  static targets = ["input", "chipsContainer", "dropdown", "hiddenInput", "helpModal"]

  static values = {
    modelName: String,
    suggestionsUrl: String
  }

  // Minimum characters before triggering autocomplete
  static MIN_AUTOCOMPLETE_CHARS = 2

  // Debounce delay in milliseconds
  static DEBOUNCE_DELAY_MS = 150

  connect() {
    this.debounceTimer = null
    this.selectedIndex = -1
    this.suggestions = []
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }

  /**
   * Handles input changes with debouncing.
   * Determines whether to show field or value suggestions based on cursor context.
   */
  onInput() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    this.debounceTimer = setTimeout(() => {
      this.updateSuggestions()
    }, this.constructor.DEBOUNCE_DELAY_MS)
  }

  /**
   * Handles keyboard navigation and selection.
   *
   * @param {KeyboardEvent} event
   */
  onKeydown(event) {
    // Handle backspace to remove last chip when input is empty
    if (event.key === "Backspace" && this.inputTarget.value === "") {
      const chips = this.chipsContainerTarget.querySelectorAll('[data-token]')
      if (chips.length > 0) {
        event.preventDefault()
        this.removeChipElement(chips[chips.length - 1])
        return
      }
    }

    // Handle Enter to submit form when no suggestions are shown or none selected
    if (event.key === "Enter") {
      if (this.suggestions.length === 0 || this.selectedIndex < 0) {
        event.preventDefault()
        this.addCurrentInputAsToken()
        this.submitForm()
        return
      }
    }

    if (!this.hasDropdownTarget || this.suggestions.length === 0) {
      return
    }

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.selectNext()
        break
      case "ArrowUp":
        event.preventDefault()
        this.selectPrevious()
        break
      case "Enter":
        if (this.selectedIndex >= 0) {
          event.preventDefault()
          this.selectCurrentSuggestion()
        }
        break
      case "Escape":
        this.hideSuggestions()
        this.hideHelp()
        break
      case "Tab":
        // If suggestions are shown, TAB selects the highlighted item (or first if none)
        if (this.suggestions.length > 0) {
          event.preventDefault()
          if (this.selectedIndex < 0) {
            this.selectedIndex = 0
            this.updateSelectionHighlight()
          }
          this.selectCurrentSuggestion()
        } else if (this.inputTarget.value.trim()) {
          // No suggestions but there's input - create a chip without submitting
          event.preventDefault()
          this.addCurrentInputAsChip()
        }
        break
    }
  }

  /**
   * Adds the current input value as a token to the hidden input.
   */
  addCurrentInputAsToken() {
    if (!this.hasInputTarget) return

    const value = this.inputTarget.value.trim()
    if (value) {
      this.appendToHiddenInput(value)
      this.inputTarget.value = ""
    }
  }

  /**
   * Adds the current input as a visible chip without submitting the form.
   * Used when pressing TAB to add multiple filters before searching.
   */
  addCurrentInputAsChip() {
    if (!this.hasInputTarget || !this.hasChipsContainerTarget) return

    const value = this.inputTarget.value.trim()
    if (!value) return

    // Check for leading boolean operator (OR/AND)
    const booleanMatch = value.match(/^(AND|OR)\s+(.+)$/i)
    if (booleanMatch) {
      const operator = booleanMatch[1].toUpperCase()
      const remainder = booleanMatch[2]

      // Insert the boolean operator label
      const operatorHtml = this.createBooleanOperatorHtml(operator)
      this.inputTarget.insertAdjacentHTML('beforebegin', operatorHtml)

      // Parse and insert the actual token
      const tokenData = this.parseInputToToken(remainder)
      const chipHtml = this.createChipHtml(tokenData)
      this.inputTarget.insertAdjacentHTML('beforebegin', chipHtml)
    } else {
      // Parse the input to create token data
      const tokenData = this.parseInputToToken(value)

      // Create and insert the chip element
      const chipHtml = this.createChipHtml(tokenData)
      this.inputTarget.insertAdjacentHTML('beforebegin', chipHtml)
    }

    // Update hidden input
    this.appendToHiddenInput(value)

    // Clear the visible input
    this.inputTarget.value = ""
  }

  /**
   * Creates HTML for a boolean operator label between chips.
   *
   * @param {string} operator - 'AND' or 'OR'
   * @returns {string} HTML string for the operator label
   */
  createBooleanOperatorHtml(operator) {
    return `<span class="text-xs font-medium text-purple-600 px-1">${operator}</span>`
  }

  /**
   * Parses an input string into token data for chip creation.
   *
   * @param {string} input - The input string to parse
   * @returns {Object} Token data with field, value, exact, negated properties
   */
  parseInputToToken(input) {
    let negated = false
    let remaining = input

    // Check for negation prefix
    if (remaining.startsWith('-')) {
      negated = true
      remaining = remaining.substring(1)
    } else if (remaining.toUpperCase().startsWith('NOT ')) {
      negated = true
      remaining = remaining.substring(4)
    }

    // Check for field:value pattern
    const fieldMatch = remaining.match(/^(\w+):(.+)$/)
    if (fieldMatch) {
      let fieldValue = fieldMatch[2]
      let exact = true

      // Check for partial match suffix
      if (fieldValue.endsWith('*')) {
        exact = false
        fieldValue = fieldValue.slice(0, -1)
      }

      // Remove surrounding quotes if present
      if (fieldValue.startsWith('"') && fieldValue.endsWith('"')) {
        fieldValue = fieldValue.slice(1, -1)
      }

      return {
        type: 'field_value',
        field: fieldMatch[1].toLowerCase(),
        value: fieldValue,
        exact: exact,
        negated: negated
      }
    }

    // Free text token
    return {
      type: 'free_text',
      field: null,
      value: remaining,
      exact: true,
      negated: negated
    }
  }

  /**
   * Creates HTML for a chip element from token data.
   *
   * @param {Object} tokenData - The token data
   * @returns {string} HTML string for the chip
   */
  createChipHtml(tokenData) {
    const chipColour = tokenData.negated ? 'bg-red-100 text-red-700' : 'bg-blue-100 text-blue-700'
    const hoverColour = tokenData.negated ? 'hover:bg-red-200' : 'hover:bg-blue-200'
    const strokeColour = tokenData.negated
        ? 'stroke-red-700/50 group-hover:stroke-red-700/75'
        : 'stroke-blue-700/50 group-hover:stroke-blue-700/75'

    const negationHtml = tokenData.negated
        ? '<span class="text-red-500 font-bold">NOT</span>'
        : ''

    const fieldHtml = tokenData.field
        ? `<span class="font-semibold">${this.escapeHtml(tokenData.field)}:</span>`
        : ''

    const displayValue = tokenData.value.includes(' ') && tokenData.exact
        ? `"${tokenData.value}"`
        : tokenData.value

    const partialHtml = !tokenData.exact
        ? '<span class="text-gray-500">*</span>'
        : ''

    return `
      <span data-token='${JSON.stringify(tokenData)}'
            class="inline-flex items-center gap-x-1 rounded px-1.5 py-0.5 text-xs font-medium ${chipColour}">
        ${negationHtml}
        ${fieldHtml}
        <span>${this.escapeHtml(displayValue)}</span>
        ${partialHtml}
        <button type="button"
                data-action="click->field-search#removeChip"
                class="group relative -mr-0.5 h-3 w-3 rounded-sm ${hoverColour}">
          <span class="sr-only">Remove</span>
          <svg viewBox="0 0 14 14" class="h-3 w-3 ${strokeColour}">
            <path d="M4 4l6 6m0-6l-6 6" stroke-width="1.5" stroke-linecap="round"/>
          </svg>
        </button>
      </span>
    `
  }

  /**
   * Appends a value to the hidden search input.
   */
  appendToHiddenInput(value) {
    if (!this.hasHiddenInputTarget) return

    const current = this.hiddenInputTarget.value.trim()
    this.hiddenInputTarget.value = current ? `${current} ${value}` : value
  }

  /**
   * Handles clicks outside the dropdown to close it.
   *
   * @param {Event} event
   */
  onClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hideSuggestions()
    }
  }

  /**
   * Determines the autocomplete mode based on input context.
   *
   * @returns {Object} { mode: 'field'|'value'|'none', field?: string, prefix?: string }
   */
  getAutocompleteMode() {
    if (!this.hasInputTarget) return {mode: 'none'}

    const value = this.inputTarget.value
    const cursorPos = this.inputTarget.selectionStart
    const textBeforeCursor = value.substring(0, cursorPos)

    // Check if we're after a colon (value mode)
    // Matches: field_name:prefix or field_name:"partial
    const colonMatch = textBeforeCursor.match(/(\w+):(?:"([^"]*)|([^:\s"]*))$/)
    if (colonMatch) {
      const field = colonMatch[1]
      const prefix = colonMatch[2] !== undefined ? colonMatch[2] : colonMatch[3]
      return {mode: 'value', field: field, prefix: prefix || ''}
    }

    // Check if we're typing a word (field mode)
    const wordMatch = textBeforeCursor.match(/(?:^|\s)(\w+)$/)
    if (wordMatch && wordMatch[1].length >= this.constructor.MIN_AUTOCOMPLETE_CHARS) {
      return {mode: 'field', prefix: wordMatch[1]}
    }

    return {mode: 'none'}
  }

  /**
   * Fetches and displays autocomplete suggestions.
   */
  async updateSuggestions() {
    const context = this.getAutocompleteMode()

    if (context.mode === 'none') {
      this.hideSuggestions()
      return
    }

    try {
      const response = await get(this.suggestionsUrlValue, {
        query: {
          model: this.modelNameValue,
          mode: context.mode,
          field: context.field || '',
          prefix: context.prefix || ''
        },
        responseKind: "json"
      })

      if (response.ok) {
        const suggestions = await response.json
        this.renderSuggestions(suggestions, context.mode)
      }
    } catch (error) {
      console.error('Failed to fetch suggestions:', error)
      this.hideSuggestions()
    }
  }

  /**
   * Shows all available fields in the dropdown.
   * Triggered by clicking the dropdown toggle button.
   *
   * @param {Event} event
   */
  async showAllFields(event) {
    event.preventDefault()
    event.stopPropagation()

    try {
      const response = await get(this.suggestionsUrlValue, {
        query: {
          model: this.modelNameValue,
          mode: 'field',
          prefix: ''
        },
        responseKind: "json"
      })

      if (response.ok) {
        const suggestions = await response.json
        this.renderSuggestions(suggestions, 'field')
        // Focus the input so keyboard navigation works
        if (this.hasInputTarget) {
          this.inputTarget.focus()
        }
      }
    } catch (error) {
      console.error('Failed to fetch fields:', error)
    }
  }

  /**
   * Renders suggestions in the dropdown.
   *
   * @param {Array} suggestions - Array of suggestion objects
   * @param {string} mode - 'field' or 'value'
   */
  renderSuggestions(suggestions, mode) {
    if (!this.hasDropdownTarget || suggestions.length === 0) {
      this.hideSuggestions()
      return
    }

    this.suggestions = suggestions
    this.selectedIndex = -1

    this.dropdownTarget.innerHTML = suggestions.map((suggestion, index) => {
      const displayText = mode === 'field'
          ? `<span class="font-medium">${suggestion.value}</span>:<span class="text-gray-500 ml-1">${suggestion.display}</span>`
          : `<span>${suggestion.value}</span>${suggestion.hits ? `<span class="text-gray-400 ml-2">(${suggestion.hits})</span>` : ''}`

      return `
        <div class="px-3 py-2 cursor-pointer hover:bg-gray-100"
             data-action="click->field-search#selectSuggestion"
             data-index="${index}"
             data-value="${this.escapeHtml(suggestion.value)}"
             data-mode="${mode}">
          ${displayText}
        </div>
      `
    }).join('')

    this.showSuggestions()
  }

  /**
   * Handles selection of an autocomplete suggestion via click.
   *
   * @param {Event} event
   */
  selectSuggestion(event) {
    const target = event.currentTarget
    const value = target.dataset.value
    const mode = target.dataset.mode

    this.insertSuggestion(value, mode)
  }

  /**
   * Selects the currently highlighted suggestion.
   */
  selectCurrentSuggestion() {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.suggestions.length) {
      return
    }

    const suggestion = this.suggestions[this.selectedIndex]
    const context = this.getAutocompleteMode()
    this.insertSuggestion(suggestion.value, context.mode)
  }

  /**
   * Inserts the selected suggestion into the input.
   *
   * @param {string} value - The suggestion value
   * @param {string} mode - 'field' or 'value'
   */
  insertSuggestion(value, mode) {
    if (!this.hasInputTarget) return

    const input = this.inputTarget
    const cursorPos = input.selectionStart
    const textBefore = input.value.substring(0, cursorPos)
    const textAfter = input.value.substring(cursorPos)

    if (mode === 'field') {
      // Replace the partial field name with the complete field name followed by colon
      // If no partial word exists (e.g., input is empty), just insert the field name
      const hasPartialWord = /(\w+)$/.test(textBefore)
      const newTextBefore = hasPartialWord
          ? textBefore.replace(/(\w+)$/, `${value}:`)
          : textBefore + `${value}:`
      input.value = newTextBefore + textAfter
      input.selectionStart = input.selectionEnd = newTextBefore.length
    } else {
      // Replace the partial value with the complete value
      // Handle both quoted and unquoted values
      const needsQuotes = value.includes(' ')
      const formattedValue = needsQuotes ? `"${value}"` : value

      // Find where the value portion starts (after the colon)
      const colonMatch = textBefore.match(/(\w+):(?:"[^"]*|[^:\s"]*)$/)
      if (colonMatch) {
        const beforeField = textBefore.substring(0, textBefore.length - colonMatch[0].length)
        const fieldName = colonMatch[1]
        const newTextBefore = `${beforeField}${fieldName}:${formattedValue}`
        input.value = newTextBefore + textAfter
        input.selectionStart = input.selectionEnd = newTextBefore.length
      }
    }

    this.hideSuggestions()
    input.focus()
  }

  /**
   * Moves selection to the next suggestion.
   */
  selectNext() {
    if (this.suggestions.length === 0) return

    this.selectedIndex = Math.min(this.selectedIndex + 1, this.suggestions.length - 1)
    this.updateSelectionHighlight()
  }

  /**
   * Moves selection to the previous suggestion.
   */
  selectPrevious() {
    if (this.suggestions.length === 0) return

    this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
    this.updateSelectionHighlight()
  }

  /**
   * Updates the visual highlight for the selected suggestion.
   */
  updateSelectionHighlight() {
    if (!this.hasDropdownTarget) return

    const items = this.dropdownTarget.querySelectorAll('[data-index]')
    items.forEach((item, index) => {
      if (index === this.selectedIndex) {
        item.classList.add('bg-blue-100')
        item.classList.remove('hover:bg-gray-100')
        // Scroll into view if needed
        item.scrollIntoView({block: 'nearest'})
      } else {
        item.classList.remove('bg-blue-100')
        item.classList.add('hover:bg-gray-100')
      }
    })
  }

  /**
   * Shows the suggestions dropdown.
   */
  showSuggestions() {
    if (!this.hasDropdownTarget) return

    this.dropdownTarget.classList.remove('hidden')

    // Add click outside listener
    document.addEventListener('click', this.onClickOutside.bind(this), {once: true})
  }

  /**
   * Hides the suggestions dropdown.
   */
  hideSuggestions() {
    if (!this.hasDropdownTarget) return

    this.dropdownTarget.classList.add('hidden')
    this.suggestions = []
    this.selectedIndex = -1
  }

  /**
   * Shows the help modal.
   *
   * @param {Event} event
   */
  showHelp(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasHelpModalTarget) return

    this.helpModalTarget.classList.remove('hidden')
  }

  /**
   * Hides the help modal.
   *
   * @param {Event} event
   */
  hideHelp(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    if (!this.hasHelpModalTarget) return

    this.helpModalTarget.classList.add('hidden')
  }

  /**
   * Escapes HTML special characters.
   *
   * @param {string} text
   * @returns {string}
   */
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  /**
   * Removes a search chip and updates the search.
   *
   * @param {Event} event
   */
  removeChip(event) {
    event.preventDefault()
    event.stopPropagation()

    const chip = event.currentTarget.closest('[data-token]')
    if (!chip) return

    this.removeChipElement(chip)
  }

  /**
   * Removes a chip element and updates the hidden input.
   *
   * @param {Element} chip - The chip element to remove
   */
  removeChipElement(chip) {
    // Remove the chip element first
    chip.remove()

    // Rebuild hidden input from remaining chips (more reliable than regex removal)
    this.rebuildHiddenInputFromChips()

    // Submit the form using requestSubmit for proper Turbo handling
    this.submitForm()
  }

  /**
   * Submits the form with Turbo support.
   * Uses requestSubmit() for Turbo compatibility, with submit() as fallback.
   */
  submitForm() {
    if (this.element.requestSubmit) {
      this.element.requestSubmit()
    } else {
      this.element.submit()
    }
  }

  /**
   * Removes a token from the hidden input value.
   *
   * @param {Object} tokenData - The token to remove
   */
  removeTokenFromHiddenInput(tokenData) {
    if (!this.hasHiddenInputTarget || !tokenData) return

    let value = this.hiddenInputTarget.value

    if (tokenData.field) {
      // Remove field:value pattern - be generous with matching
      const escapedField = tokenData.field.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      const escapedValue = tokenData.value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

      // Try various patterns - order matters (more specific first)
      const patterns = [
        // With quotes and potential negation/partial
        new RegExp(`-?${escapedField}:"${escapedValue}"\\*?`, 'gi'),
        new RegExp(`NOT\\s+${escapedField}:"${escapedValue}"\\*?`, 'gi'),
        // Without quotes
        new RegExp(`-?${escapedField}:${escapedValue}\\*?`, 'gi'),
        new RegExp(`NOT\\s+${escapedField}:${escapedValue}\\*?`, 'gi'),
      ]

      for (const pattern of patterns) {
        const before = value
        value = value.replace(pattern, '')
        if (value !== before) break // Stop after first successful match
      }
    } else {
      // Remove free text token
      const escapedValue = tokenData.value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      // Match the value with word boundaries or quotes
      value = value.replace(new RegExp(`"${escapedValue}"`, 'gi'), '')
      value = value.replace(new RegExp(`(?:^|\\s)${escapedValue}(?:\\s|$)`, 'gi'), ' ')
    }

    // Clean up extra spaces
    this.hiddenInputTarget.value = value.replace(/\s+/g, ' ').trim()
  }

  /**
   * Rebuilds the hidden input value from all current chips.
   * Used as a fallback if token removal doesn't work correctly.
   */
  rebuildHiddenInputFromChips() {
    if (!this.hasHiddenInputTarget || !this.hasChipsContainerTarget) return

    const chips = this.chipsContainerTarget.querySelectorAll('[data-token]')
    const parts = []

    chips.forEach(chip => {
      const tokenData = JSON.parse(chip.dataset.token)
      if (tokenData.field) {
        let part = ''
        if (tokenData.negated) part += '-'
        part += tokenData.field + ':'
        if (tokenData.value.includes(' ')) {
          part += `"${tokenData.value}"`
        } else {
          part += tokenData.value
        }
        if (!tokenData.exact) part += '*'
        parts.push(part)
      } else if (tokenData.value) {
        parts.push(tokenData.value)
      }
    })

    this.hiddenInputTarget.value = parts.join(' ')
  }
}
