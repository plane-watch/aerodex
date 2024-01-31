import {Controller} from "@hotwired/stimulus"
import {useIntersection} from "stimulus-use"
import {get} from "@rails/request.js"

export default class extends Controller {
    static values = {
        containerTarget: String,
        url: String,
    }

    connect() {
        this.page = 1
        this.fetchingData = false
        useIntersection(this)
    }

    async appear() {
        if (this.fetchingData || this.hasNoMoreResultsItem) return
        this.fetchingData = true
        this.page = this.page + 1

        let queryOptions = {
            query: {
                page: this.page,
                turbo_target: this.containerTargetValue,
            },
            responseKind: "turbo-stream"
        }
        const urlParams = new URLSearchParams(window.location.search);
        const searchString = urlParams.get('search');
        if (searchString) {
            queryOptions.query.search = searchString
        }

        await get(this.urlValue, queryOptions)
        this.fetchingData = false
    }

    get hasNoMoreResultsItem() {
        return document.getElementById(this.containerTargetValue).querySelector(`[data-no-more-records]`) !== null
    }
}