import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

/**
 * Handles real-time progress updates for batch processing and apply operations.
 *
 * Connects to StagedBatchChannel via ActionCable and updates
 * the progress bar as the batch is processed or applied.
 *
 * Includes fallback polling that kicks in when progress reaches 100%,
 * in case the ActionCable completion event is missed.
 *
 * @example View usage
 *   <div data-controller="batch-apply"
 *        data-batch-apply-batch-id-value="<%= batch.id %>"
 *        data-batch-apply-status-value="<%= batch.status %>">
 *     <div data-batch-apply-target="actions">...</div>
 *     <div data-batch-apply-target="progress" class="hidden">
 *       <div data-batch-apply-target="progressBar"></div>
 *       <span data-batch-apply-target="progressText"></span>
 *     </div>
 *   </div>
 */
export default class extends Controller {
  static targets = ["actions", "progress", "progressBar", "progressText"]
  static values = { batchId: String, status: String }

  connect() {
    if (this.statusValue === "applying" || this.statusValue === "processing") {
      this.showProgress()
      this.subscribe()
    }
  }

  disconnect() {
    this.stopPolling()
    this.unsubscribe()
  }

  /**
   * Subscribes to the ActionCable channel for this batch.
   * Listens for progress and completion events.
   */
  subscribe() {
    this.consumer = createConsumer()
    this.channel = this.consumer.subscriptions.create(
      { channel: "StagedBatchChannel", id: this.batchIdValue },
      {
        received: (data) => this.handleMessage(data)
      }
    )
  }

  /**
   * Unsubscribes from the ActionCable channel and disconnects the consumer.
   */
  unsubscribe() {
    if (this.channel) {
      this.channel.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
  }

  /**
   * Shows the progress bar and hides the action buttons.
   */
  showProgress() {
    if (this.hasActionsTarget) {
      this.actionsTarget.classList.add("hidden")
    }
    if (this.hasProgressTarget) {
      this.progressTarget.classList.remove("hidden")
    }
  }

  /**
   * Handles incoming messages from the ActionCable channel.
   *
   * @param {Object} data - The message data
   * @param {string} data.event - The event type ('progress', 'processing_progress', or 'complete')
   * @param {number} [data.progress] - The progress percentage (0-100)
   */
  handleMessage(data) {
    if (data.event === "progress" || data.event === "processing_progress") {
      this.updateProgress(data.progress, data.event)
    } else if (data.event === "complete") {
      this.handleComplete(data)
    }
  }

  /**
   * Updates the progress bar and text with the current percentage.
   * Starts fallback polling when progress reaches 100%.
   *
   * @param {number} progress - The progress percentage (0-100)
   * @param {string} event - The event type ('progress' or 'processing_progress')
   */
  updateProgress(progress, event = "progress") {
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${progress}%`
    }
    if (this.hasProgressTextTarget) {
      const label = event === "processing_progress" ? "Processing" : "Applying"
      this.progressTextTarget.textContent = `${label}... ${progress}%`
    }

    // Start fallback polling when we hit 100%
    if (progress >= 100 && !this.pollingStarted) {
      this.startFallbackPolling()
    }
  }

  /**
   * Starts polling the batch status as a fallback in case
   * the ActionCable completion event is missed.
   */
  startFallbackPolling() {
    this.pollingStarted = true
    this.pollInterval = setInterval(() => this.checkBatchStatus(), 2000)
  }

  /**
   * Fetches the current batch status and reloads if complete.
   */
  async checkBatchStatus() {
    try {
      const response = await fetch(`/admin/staged_batches/${this.batchIdValue}/status.json`)
      const data = await response.json()

      if (data.status !== "applying" && data.status !== "processing") {
        this.stopPolling()
        window.location.reload()
      }
    } catch (error) {
      console.error("Failed to check batch status:", error)
    }
  }

  /**
   * Stops the fallback polling interval.
   */
  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
      this.pollInterval = null
    }
  }

  /**
   * Handles the completion event by reloading the page.
   * This shows the final state (applied or failed).
   *
   * @param {Object} data - The completion event data
   */
  handleComplete(data) {
    this.stopPolling()
    window.location.reload()
  }
}
