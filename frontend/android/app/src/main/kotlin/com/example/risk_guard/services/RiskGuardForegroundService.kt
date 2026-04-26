package com.example.risk_guard.services

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.example.risk_guard.ProtectionEventStore

class RiskGuardForegroundService : Service() {
    private var telephonyManager: TelephonyManager? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var telephonyCallback: TelephonyCallback? = null
    private var lastCallState: String? = null
    private var lastKnownPhoneNumber: String? = null
    private var lastBroadcastPhoneNumber: String? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(101, buildNotification())
        ProtectionEventStore.setForegroundServiceRunning(this, true)
        registerCallStateListener()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP_SERVICE") {
            stopCallStateListener()
            ProtectionEventStore.setForegroundServiceRunning(this, false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.hasExtra("phoneNumber") == true) {
            lastKnownPhoneNumber = intent.getStringExtra("phoneNumber")
        }

        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val channelId = "risk_guard_channel"
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "RiskGuard Protection",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("RiskGuard Active")
            .setContentText("Monitoring system for threats and calls...")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun registerCallStateListener() {
        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        val manager = telephonyManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    handleCallStateChanged(state)
                }
            }
            telephonyCallback = callback
            manager.registerTelephonyCallback(mainExecutor, callback)
        } else {
            @Suppress("DEPRECATION")
            val listener = object : PhoneStateListener() {
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    handleCallStateChanged(state, phoneNumber)
                }
            }
            phoneStateListener = listener
            @Suppress("DEPRECATION")
            manager.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    private fun handleCallStateChanged(state: Int, phoneNumber: String? = null) {
        if (!ProtectionEventStore.isProtectionActive(this)) return
        if (!ProtectionEventStore.isCallMonitoringEnabled(this)) return

        val mappedState = when (state) {
            TelephonyManager.CALL_STATE_RINGING -> "RINGING"
            TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
            else -> "IDLE"
        }

        if (!phoneNumber.isNullOrBlank()) {
            lastKnownPhoneNumber = phoneNumber
        }

        val effectiveNumber = phoneNumber ?: lastKnownPhoneNumber
        if (lastCallState == mappedState && effectiveNumber == lastBroadcastPhoneNumber) {
            return
        }

        lastCallState = mappedState
        lastBroadcastPhoneNumber = effectiveNumber
        ProtectionEventStore.storeCallEvent(this, mappedState, effectiveNumber)
        ProtectionEventStore.broadcastCall(this, mappedState, effectiveNumber)
    }

    private fun stopCallStateListener() {
        val manager = telephonyManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = telephonyCallback
            if (callback != null) {
                manager.unregisterTelephonyCallback(callback)
            }
            telephonyCallback = null
        } else {
            @Suppress("DEPRECATION")
            manager.listen(phoneStateListener, PhoneStateListener.LISTEN_NONE)
            phoneStateListener = null
        }
    }

    override fun onDestroy() {
        stopCallStateListener()
        ProtectionEventStore.setForegroundServiceRunning(this, false)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
