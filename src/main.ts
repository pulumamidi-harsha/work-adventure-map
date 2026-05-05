/// <reference types="@workadventure/iframe-api-typings" />

import { bootstrapExtra } from "@workadventure/scripting-api-extra";
import { getApplicationUrl } from "./env-config";

console.log('Script started successfully');

let currentPopup: any = undefined;

// Waiting for the API to be ready
WA.onInit().then(() => {
    console.log('Scripting API ready');
    console.log('Player tags: ',WA.player.tags)

    WA.room.area.onEnter('clock').subscribe(() => {
        const today = new Date();
        const time = today.getHours() + ":" + today.getMinutes();
        currentPopup = WA.ui.openPopup("clockPopup", "It's " + time, []);
    })

    WA.room.area.onLeave('clock').subscribe(closePopup)

    // The line below bootstraps the Scripting API Extra library that adds a number of advanced properties/features to WorkAdventure
    bootstrapExtra().then(() => {
        console.log('Scripting API Extra ready');
    }).catch(e => console.error(e));

    // Handle environment-aware website opening
    setupEnvironmentAwareWebsites();

    // Log environment detection for debugging
    console.log('🌍 Environment detection initialized');

}).catch(e => console.error(e));

function setupEnvironmentAwareWebsites() {
    // Get the environment-specific URL
    const applicationUrl = getApplicationUrl();
    console.log('Environment-specific URL:', applicationUrl);

    // Set up areas that should open the environment-aware website
    const websiteAreas = [
        'website-area', 'platform-area', 'app-area', 'link-area'
    ]; // Add more area names as needed

    websiteAreas.forEach(areaName => {
        WA.room.area.onEnter(areaName).subscribe(() => {
            WA.nav.openTab(applicationUrl);
        });
    });
}

function closePopup(){
    if (currentPopup !== undefined) {
        currentPopup.close();
        currentPopup = undefined;
    }
}

export {};
