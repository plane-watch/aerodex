import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

/**
 * Handles real-time progress updates for batch apply operations.
 *
 * Connects to StagedBatchChannel via ActionCable and updates
 * the progress bar as the batch is applied.
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
    if (this.statusValue === "applying") {
      this.showProgress()
      this.subscribe()
    }
  }

  disconnect() {
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
   * @param {string} data.event - The event type ('progress' or 'complete')
   * @param {number} [data.progress] - The progress percentage (0-100)
   */
  handleMessage(data) {
    if (data.event === "progress") {
      this.updateProgress(data.progress)
    } else if (data.event === "complete") {
      this.handleComplete(data)
    }
  }

  /**
   * Updates the progress bar and text with the current percentage.
   *
   * @param {number} progress - The progress percentage (0-100)
   */
  updateProgress(progress) {
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${progress}%`
    }
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `Applying... ${progress}%`
    }
  }

  /**
   * Handles the completion event by reloading the page.
   * This shows the final state (applied or failed).
   *
   * @param {Object} data - The completion event data
   */
  handleComplete(data) {
    window.location.reload()
  }
}
