import { LightningElement } from 'lwc';
import LightningAlert from 'lightning/alert';

export default class SiteHeader extends LightningElement {
    get basePath() {
        // In Experience Cloud, the site base path ends at '/s'. Ensure trailing / is present.
        try {
            const { pathname } = window.location;
            // Split at '/s' and keep everything up to and including '/s'
            const idx = pathname.indexOf('/s');
            const root = idx >= 0 ? pathname.substring(0, idx + 2) : '/s';
            return root.endsWith('/') ? root : root + '/';
        } catch (e) {
            return '/s/';
        }
    }

    get bugHuntUrl() {
    // Explicitly use the working action URL for Case creation
    return `${this.basePath}createrecord/NewCase`;
    }

    get leaderboardUrl() {
    // Dedicated leaderboard page slug
    return `${this.basePath}bug-hunt-leaderboard`;
    }

    async handleBookClick() {
        await LightningAlert.open({
            message: `This feature isn't implemented, check again later.`,
            theme: 'warn',
            label: 'Not Implemented'
        });
    }
}
