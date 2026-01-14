/// <reference types="@workadventure/iframe-api-typings" />

import { bootstrapExtra } from "@workadventure/scripting-api-extra";

console.log('Script started successfully');

let currentPopup: any = undefined;
let activeExitAreaName: string | undefined;

type TiledProperty = { name: string; type: string; value: unknown };

function getStringProperty(properties: unknown, name: string): string | undefined {
    if (!Array.isArray(properties)) return;
    for (const prop of properties as TiledProperty[]) {
        if (prop && prop.name === name && typeof prop.value === 'string') {
            return prop.value;
        }
    }
    return;
}

function labelFromExitUrl(exitUrl: string): string {
    const withoutExt = exitUrl.replace(/\.tmj$/i, '');
    return withoutExt
        .replace(/[-_]+/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

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

    // Exit navigation: show a styled banner when entering an exit zone
    WA.room.getTiledMap().then((map) => {
        const roomNavigationLayer = (map.layers ?? []).find((l: any) => l && l.type === 'objectgroup' && l.name === 'roomNavigation') as any;
        const objects: any[] = Array.isArray(roomNavigationLayer?.objects) ? roomNavigationLayer.objects : [];

        for (const obj of objects) {
            if (!obj || typeof obj.name !== 'string') continue;
            if (obj.type !== 'area') continue;

            const exitUrl = getStringProperty(obj.properties, 'exitUrl');
            if (!exitUrl) continue;

            const destinationLabel = labelFromExitUrl(exitUrl);
            const areaName = obj.name;

            WA.room.area.onEnter(areaName).subscribe(() => {
                activeExitAreaName = areaName;
                WA.ui.banner.openBanner({
                    id: 'exit-navigation',
                    text: destinationLabel,
                    bgColor: '#3f3f46',
                    textColor: '#ffffff',
                    closable: false,
                });
            });

            WA.room.area.onLeave(areaName).subscribe(() => {
                if (activeExitAreaName !== areaName) return;
                activeExitAreaName = undefined;
                WA.ui.banner.closeBanner();
            });
        }
    }).catch(e => console.error(e));

    // The line below bootstraps the Scripting API Extra library that adds a number of advanced properties/features to WorkAdventure
    bootstrapExtra().then(() => {
        console.log('Scripting API Extra ready');
    }).catch(e => console.error(e));

}).catch(e => console.error(e));

function closePopup(){
    if (currentPopup !== undefined) {
        currentPopup.close();
        currentPopup = undefined;
    }
}

export {};
