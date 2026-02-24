# Mobile Push Notifications Implementation Guide

This document describes the native plugins required for push notifications on iOS and Android.

## Overview

The game now sends push notifications for all critical events:
- Combat encounters
- Ship breakdowns
- Crew deaths
- Ship destruction
- Life support warnings
- Food depletion
- Violations and colony bans

## Platform Support

### Desktop (Windows/macOS/Linux)
✅ **Already Implemented** - Uses `DisplayServer.window_request_attention()` to flash taskbar/dock

### Android
⚠️ **Requires Plugin** - See Android Plugin Implementation below

### iOS
⚠️ **Requires Plugin** - See iOS Plugin Implementation below

---

## Android Plugin Implementation

### Requirements
- Godot 4.6 Android plugin module
- Android API 26+ (for notification channels)
- Permissions: `POST_NOTIFICATIONS` (Android 13+)

### Plugin Architecture

Create a GDExtension plugin or Android plugin module that exposes:

**Singleton Name:** `AndroidNotifications`

**Methods:**
- `send_notification(title: String, body: String, is_critical: bool) -> void`

### Reference Implementation (Java)

```java
// android/plugins/notifications/NotificationPlugin.java
package com.claim.notifications;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;

import java.util.Arrays;
import java.util.List;

public class NotificationPlugin extends GodotPlugin {
    private static final String CHANNEL_ID_CRITICAL = "claim_critical_events";
    private static final String CHANNEL_ID_NORMAL = "claim_normal_events";
    private NotificationManager notificationManager;
    private int notificationIdCounter = 1000;

    public NotificationPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "AndroidNotifications";
    }

    @Override
    public void onMainCreate(Activity activity) {
        super.onMainCreate(activity);
        notificationManager = (NotificationManager) activity.getSystemService(Context.NOTIFICATION_SERVICE);
        createNotificationChannels();
    }

    private void createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Critical events channel (high priority, sound + vibration)
            NotificationChannel criticalChannel = new NotificationChannel(
                CHANNEL_ID_CRITICAL,
                "Critical Events",
                NotificationManager.IMPORTANCE_HIGH
            );
            criticalChannel.setDescription("Ship emergencies, combat, crew deaths");
            criticalChannel.enableVibration(true);
            criticalChannel.setVibrationPattern(new long[]{0, 200, 100, 200});
            criticalChannel.setShowBadge(true);
            notificationManager.createNotificationChannel(criticalChannel);

            // Normal events channel (default priority)
            NotificationChannel normalChannel = new NotificationChannel(
                CHANNEL_ID_NORMAL,
                "Normal Events",
                NotificationManager.IMPORTANCE_DEFAULT
            );
            normalChannel.setDescription("Mission updates, market changes");
            notificationManager.createNotificationChannel(normalChannel);
        }
    }

    public void send_notification(String title, String body, boolean isCritical) {
        Activity activity = getActivity();
        if (activity == null) return;

        String channelId = isCritical ? CHANNEL_ID_CRITICAL : CHANNEL_ID_NORMAL;
        int priority = isCritical ? NotificationCompat.PRIORITY_HIGH : NotificationCompat.PRIORITY_DEFAULT;

        // Intent to open app when notification tapped
        Intent intent = new Intent(activity, activity.getClass());
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        PendingIntent pendingIntent = PendingIntent.getActivity(
            activity, 0, intent, PendingIntent.FLAG_IMMUTABLE
        );

        NotificationCompat.Builder builder = new NotificationCompat.Builder(activity, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)  // Replace with your app icon
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(priority)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true);

        if (isCritical) {
            builder.setVibrate(new long[]{0, 200, 100, 200});
            builder.setCategory(NotificationCompat.CATEGORY_ALARM);
        }

        notificationManager.notify(notificationIdCounter++, builder.build());
    }
}
```

### Plugin Configuration

**android/plugins/notifications/plugin.cfg:**
```ini
[config]
name="AndroidNotifications"
binary_type="local"
binary="NotificationPlugin.jar"

[dependencies]
local=[]
remote=["androidx.core:core:1.12.0"]
```

### Android Manifest Permissions

Add to `android/build/AndroidManifest.xml`:
```xml
<!-- Android 13+ requires explicit permission -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.VIBRATE" />
```

### Build Steps
1. Compile Java plugin to JAR
2. Place JAR in `android/plugins/`
3. Enable plugin in export settings
4. Request notification permission at runtime (Android 13+)

---

## iOS Plugin Implementation

### Requirements
- Godot 4.6 iOS plugin module
- iOS 10+ (UserNotifications framework)
- Permissions: User consent required at runtime

### Plugin Architecture

Create a GDExtension plugin that exposes:

**Singleton Name:** `IOSNotifications`

**Methods:**
- `send_local_notification(title: String, body: String) -> void`
- `request_permission() -> void`

### Reference Implementation (Objective-C)

```objc
// ios/plugins/notifications/NotificationPlugin.h
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import "core/object/object.h"

@interface NotificationPlugin : Object<UNUserNotificationCenterDelegate>

+ (NotificationPlugin *)sharedInstance;
- (void)requestPermission;
- (void)sendLocalNotification:(NSString *)title body:(NSString *)body;

@end
```

```objc
// ios/plugins/notifications/NotificationPlugin.m
#import "NotificationPlugin.h"

@implementation NotificationPlugin

static NotificationPlugin *_instance = nil;

+ (NotificationPlugin *)sharedInstance {
    if (_instance == nil) {
        _instance = [[NotificationPlugin alloc] init];
        [UNUserNotificationCenter currentNotificationCenter].delegate = _instance;
    }
    return _instance;
}

- (void)requestPermission {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;

    [center requestAuthorizationWithOptions:options
        completionHandler:^(BOOL granted, NSError * _Nullable error) {
            if (granted) {
                NSLog(@"Notification permission granted");
            } else {
                NSLog(@"Notification permission denied");
            }
        }];
}

- (void)sendLocalNotification:(NSString *)title body:(NSString *)body {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

    // Create notification content
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title;
    content.body = body;
    content.sound = [UNNotificationSound defaultCriticalSound];  // Critical sound
    content.badge = @([[UIApplication sharedApplication] applicationIconBadgeNumber] + 1);
    content.categoryIdentifier = @"CRITICAL_EVENT";

    // Deliver immediately
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger
        triggerWithTimeInterval:0.1 repeats:NO];

    // Create unique identifier using timestamp
    NSString *identifier = [NSString stringWithFormat:@"critical_%f", [[NSDate date] timeIntervalSince1970]];

    // Create request
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
        content:content trigger:trigger];

    // Schedule notification
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if (error != nil) {
            NSLog(@"Error scheduling notification: %@", error.localizedDescription);
        }
    }];
}

// Delegate method - handle notification when app is in foreground
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
        willPresentNotification:(UNNotification *)notification
        withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    // Show notification even when app is active
    completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
}

@end
```

### GDNative Wrapper (C++)

```cpp
// ios/plugins/notifications/register_types.cpp
#include "register_types.h"
#include "notification_plugin_ios.h"
#include "core/object/class_db.h"

static NotificationPluginIOS *notification_plugin = nullptr;

void initialize_notification_plugin_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    ClassDB::register_class<NotificationPluginIOS>();
    notification_plugin = memnew(NotificationPluginIOS);
    Engine::get_singleton()->add_singleton(Engine::Singleton("IOSNotifications", notification_plugin));
}

void uninitialize_notification_plugin_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    if (notification_plugin) {
        memdelete(notification_plugin);
    }
}
```

```cpp
// ios/plugins/notifications/notification_plugin_ios.h
#ifndef NOTIFICATION_PLUGIN_IOS_H
#define NOTIFICATION_PLUGIN_IOS_H

#include "core/object/object.h"

class NotificationPluginIOS : public Object {
    GDCLASS(NotificationPluginIOS, Object);

protected:
    static void _bind_methods();

public:
    void request_permission();
    void send_local_notification(const String &title, const String &body);

    NotificationPluginIOS();
    ~NotificationPluginIOS();
};

#endif
```

```cpp
// ios/plugins/notifications/notification_plugin_ios.mm
#include "notification_plugin_ios.h"
#import "NotificationPlugin.h"

void NotificationPluginIOS::_bind_methods() {
    ClassDB::bind_method(D_METHOD("request_permission"), &NotificationPluginIOS::request_permission);
    ClassDB::bind_method(D_METHOD("send_local_notification", "title", "body"),
        &NotificationPluginIOS::send_local_notification);
}

NotificationPluginIOS::NotificationPluginIOS() {
}

NotificationPluginIOS::~NotificationPluginIOS() {
}

void NotificationPluginIOS::request_permission() {
    [[NotificationPlugin sharedInstance] requestPermission];
}

void NotificationPluginIOS::send_local_notification(const String &title, const String &body) {
    NSString *nsTitle = [NSString stringWithUTF8String:title.utf8().get_data()];
    NSString *nsBody = [NSString stringWithUTF8String:body.utf8().get_data()];
    [[NotificationPlugin sharedInstance] sendLocalNotification:nsTitle body:nsBody];
}
```

### Info.plist Configuration

Add to `ios/Info.plist`:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

### Build Steps
1. Compile plugin as iOS module (.a static library)
2. Add to Xcode project
3. Link UserNotifications.framework
4. Call `request_permission()` on first launch
5. Export with plugin enabled

---

## Usage in Game

The notification system is already integrated. Once plugins are installed:

```gdscript
# GameState automatically calls this for critical warnings:
send_push_notification("Critical Event", "⚔️ COMBAT: Ship engaged")

# Desktop: Window flashes
# Android: Notification with vibration
# iOS: Local notification with critical sound
```

## Testing

### Android
1. Build with plugin enabled
2. Install on device (not emulator for vibration)
3. Run game in background
4. Trigger critical event (ship breakdown, combat, etc.)
5. Verify notification appears in status bar

### iOS
1. Build with plugin enabled
2. Install on device via Xcode
3. Grant notification permission when prompted
4. Run game in background
5. Trigger critical event
6. Verify notification appears with critical sound

## Permission Handling

### Android (13+)
Request permission at runtime:
```gdscript
if OS.get_name() == "Android":
    # Request in main menu or tutorial
    OS.request_permission("android.permission.POST_NOTIFICATIONS")
```

### iOS
Call plugin's request_permission on first launch:
```gdscript
if OS.get_name() == "iOS":
    if Engine.has_singleton("IOSNotifications"):
        Engine.get_singleton("IOSNotifications").request_permission()
```

## Future Enhancements

- **Remote Push Notifications** (multiplayer mode): Requires Firebase Cloud Messaging (FCM) or Apple Push Notification Service (APNs)
- **Notification Actions**: Add quick actions like "Send Rescue" from notification
- **Notification Grouping**: Group multiple critical events into single notification
- **Custom Sounds**: Add ship alarm sounds for different event types
- **Priority Levels**: Different notification priorities for warning vs critical

## Resources

- [Godot Android Plugins](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html)
- [Godot iOS Plugins](https://docs.godotengine.org/en/stable/tutorials/platform/ios/plugins_for_ios.html)
- [Android NotificationCompat](https://developer.android.com/reference/androidx/core/app/NotificationCompat)
- [iOS UserNotifications](https://developer.apple.com/documentation/usernotifications)
