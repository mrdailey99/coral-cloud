import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createReport from '@salesforce/apex/BugHuntReportController.createReport';
import getReportIdByCase from '@salesforce/apex/BugHuntReportController.getReportIdByCase';

export default class BugHuntNewCase extends LightningElement {
    // Faux login state
    @track loggedIn = false;
    @track loginUsername = '';

    // Form extras
    @track prefillEmail = '';
    @track urgent = false;
    @track newRecordId;
    @track beforeFields;

    // Bug report modal state
    @track showReport = false;
    @track reportText = '';
    @track includeTech = true;

    // Custom Type selector state (includes an unsupported option)
    @track selectedType = '--None--';
    typeOptions = [
        { label: 'Mechanical', value: 'Mechanical' },
        { label: 'Electrical', value: 'Electrical' },
        { label: 'Electronic', value: 'Electronic' },
        { label: 'Structural', value: 'Structural' },
        { label: 'Other', value: 'Other' },
        { label: 'Software', value: 'Software' },
        { label: 'Technical', value: 'Technical' }
    ];
    handleTypeChange(event) {
        this.selectedType = event.detail.value;
    }

    handleEmailChange(event) {
        this.prefillEmail = event.detail.value;
    }

    // Timer state
    @track hasTimer = false;
    @track timerDisplay = '';
    @track timerExpired = false;
    _timerHandle;
    _timerEndAt = 0; // epoch ms

    get timerKey() {
        return `bugHuntTimer:${this.loginUsername||''}`;
    }
    formatMs(ms) {
        const total = Math.max(0, Math.floor(ms/1000));
        const m = Math.floor(total/60);
        const s = total%60;
        const mm = String(m).padStart(2,'0');
        const ss = String(s).padStart(2,'0');
        return `${mm}:${ss}`;
    }
    tickTimer() {
        const now = Date.now();
        const remaining = this._timerEndAt - now;
        if (remaining <= 0) {
            this.timerDisplay = '00:00';
            this.timerExpired = true;
            this.hasTimer = true;
            if (this._timerHandle) {
                window.clearInterval(this._timerHandle);
                this._timerHandle = undefined;
            }
            return;
        }
        this.timerDisplay = this.formatMs(remaining);
        this.timerExpired = false;
        this.hasTimer = true;
    }
    startOrResumeTimer() {
        try {
            const raw = window.localStorage.getItem(this.timerKey);
            const savedEnd = raw ? parseInt(raw, 10) : 0;
            const now = Date.now();
            if (savedEnd && savedEnd > now) {
                this._timerEndAt = savedEnd;
            } else {
                // 15 minutes from now
                this._timerEndAt = now + (15 * 60 * 1000);
                window.localStorage.setItem(this.timerKey, String(this._timerEndAt));
            }
        } catch (e) {
            // Fallback: non-persistent timer
            this._timerEndAt = Date.now() + (15 * 60 * 1000);
        }
        // Begin ticking
        this.tickTimer();
        if (this._timerHandle) {
            window.clearInterval(this._timerHandle);
        }
        this._timerHandle = window.setInterval(() => this.tickTimer(), 1000);
    }
    resumeTimerIfPresent() {
        try {
            const raw = window.localStorage.getItem(this.timerKey);
            const savedEnd = raw ? parseInt(raw, 10) : 0;
            if (savedEnd && savedEnd > Date.now()) {
                this._timerEndAt = savedEnd;
                this.tickTimer();
                if (this._timerHandle) {
                    window.clearInterval(this._timerHandle);
                }
                this._timerHandle = window.setInterval(() => this.tickTimer(), 1000);
            }
        } catch (e) {
            // ignore
        }
    }

    handleLoginUsername(event) {
        this.loginUsername = event.detail.value;
    }
    connectedCallback() {
        try {
            const saved = window.localStorage.getItem('bugHuntUser');
            if (saved && saved.length >= 5) {
                this.loginUsername = saved;
                this.loggedIn = true;
                // If the user has a running timer, resume it
                this.resumeTimerIfPresent();
            }
        } catch (e) {
            // ignore storage errors
        }
    }
    get isLoginDisabled() {
        // temporarily true to disable bug hunt until start time
        // return true;

        return !this.loginUsername || this.loginUsername.length < 5;
    }
    completeLogin() {
        const input = this.template.querySelector('lightning-input[type="text"]');
        if (input && !input.reportValidity()) {
            return;
        }
        this.loggedIn = true;
        try {
            window.localStorage.setItem('bugHuntUser', this.loginUsername);
        } catch (e) {
            // ignore storage errors
        }
        // Start or resume a 15-minute countdown for this user
        this.startOrResumeTimer();
    }
    changeUser() {
        this.loggedIn = false;
        // Stop ticking
        if (this._timerHandle) {
            window.clearInterval(this._timerHandle);
            this._timerHandle = undefined;
        }
        // Keep the current value visible for editing
        setTimeout(() => {
            const input = this.template.querySelector('lightning-input[type="text"]');
            if (input) input.focus();
        });
    }
    disconnectedCallback() {
        if (this._timerHandle) {
            window.clearInterval(this._timerHandle);
            this._timerHandle = undefined;
        }
    }

    handleUrgentChange(event) {
        this.urgent = event.target.checked;
    }

    handleSubmit(event) {
        event.preventDefault();
        const fields = { ...event.detail.fields };

        // Capture what the user actually entered (before any mutations)
        this.beforeFields = {
            Subject: fields.Subject,
            Origin: fields.Origin,
            Type: this.selectedType,
            Priority: fields.Priority,
            Description: fields.Description,
            Reason: fields.Reason
        };

        // Ensure the record receives whatever was selected in our custom combobox
        fields.Type = this.selectedType;

        // Visible (non-blocking) bug: force a valid but wrong Origin regardless of user selection
        fields.Origin = 'Web';

        // Silent bug: wrong casing for Priority is ignored by engine
        // eslint-disable-next-line dot-notation
        fields['priority'] = this.urgent ? 'High' : fields.Priority;

        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSuccess(event) {
        // eslint-disable-next-line no-console
        this.newRecordId = event.detail.id;
        console.log('Case created', event.detail.id);
    }

    handleError(event) {
        // eslint-disable-next-line no-console
        console.error('Error creating case', event.detail);
        // Vague error message by design; avoid surfacing backend reason
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Failed to submit case',
                message: 'Something went wrong. Please try again.',
                variant: 'error'
            })
        );
    }

    // Report Bug UI handlers
    closeReport() {
        this.showReport = false;
    }
    handleReportChange(event) {
        this.reportText = event.detail.value;
    }
    handleToggleTech(event) {
        this.includeTech = event.target.checked;
    }

    // Wait briefly for the Case Id to be available after save
    async waitForRecordId(timeoutMs = 10000, intervalMs = 100) {
        let waited = 0;
        while (!this.newRecordId && waited < timeoutMs) {
            // eslint-disable-next-line no-await-in-loop
            await new Promise((resolve) => setTimeout(resolve, intervalMs));
            waited += intervalMs;
        }
        return this.newRecordId;
    }

    async sendReport() {
        if (!this.newRecordId) {
            // Best-effort wait; only enforce if includeTech is true
            await this.waitForRecordId();
        }
        if (this.includeTech && !this.newRecordId) {
            // Give the platform a brief moment to surface the Id
            if (!this.newRecordId) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Create the case first',
                        message: 'Please click Submit Case before sending so we can attach saved backend details.',
                        variant: 'warning'
                    })
                );
                return;
            }
        }
        const getVal = (api) => {
            const el = this.template.querySelector(`[data-field="${api}"]`);
            return el && el.value !== undefined ? el.value : '';
        };
    // Prefer the last submitted values (exactly what user entered) if available
    const subject = this.beforeFields?.Subject ?? getVal('Subject');
    const origin = this.beforeFields?.Origin ?? getVal('Origin');
    const type = this.beforeFields?.Type ?? getVal('Type');
    const priority = this.beforeFields?.Priority ?? getVal('Priority');

        let body = this.reportText || '';
        // Keep body as the free-text, Apex will append technical details (before/after)
        try {
            const payload = {
                body,
                subject,
                origin,
                type,
                priority,
                // Important: map Bug Report Description to the free-text "What happened?" value
                description: body,
                unsavedEmail: this.prefillEmail,
                urgent: this.urgent,
                recordId: this.newRecordId,
                username: this.loginUsername,
                includeTech: this.includeTech
            };
        let newId = await createReport({ payload });
        // eslint-disable-next-line no-console
        console.log('Bug report created Id', newId);
            if (!newId && this.newRecordId) {
                // Fallback: ask server for the report Id tied to the Case
                try {
                    newId = await getReportIdByCase({ caseId: this.newRecordId });
                } catch (e2) {
                    // eslint-disable-next-line no-console
                    console.warn('Fallback getReportIdByCase failed', e2);
                }
            }
            const success = !!newId;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: success ? 'Bug report submitted' : 'Nothing to submit',
                    message: success ? `Report Id: ${newId}` : 'Enter a message or submit the case first before sending a report.',
                    variant: success ? 'success' : 'info'
                })
            );
            this.reportText = '';
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Failed to send bug report', e);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Send failed',
                    message: (e && e.body && e.body.message) ? e.body.message : 'Unable to send bug report.',
                    variant: 'error'
                })
            );
        } finally {
            this.closeReport();
        }
    }

    // When opening the modal, snapshot current field values only if we don't already have
    // a reliable copy from the last submit. Avoid clobbering with empty DOM values.
    openReport(event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        if (!this.beforeFields) {
            const getVal = (api) => {
                const el = this.template.querySelector(`[data-field="${api}"]`);
                return el && el.value !== undefined ? el.value : '';
            };
            this.beforeFields = {
                Subject: getVal('Subject'),
                Origin: getVal('Origin'),
                Type: getVal('Type'),
                Priority: getVal('Priority'),
                Description: getVal('Description'),
                Reason: getVal('Reason')
            };
        }
        this.showReport = true;
    }
}
