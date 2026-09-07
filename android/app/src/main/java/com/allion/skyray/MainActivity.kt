package com.allion.skyray

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.allion.skyray.core.AdsManager
import com.allion.skyray.core.ShareLinkParser
import com.allion.skyray.data.ProfileStore
import com.allion.skyray.service.ProfilesViewModel
import com.allion.skyray.service.VpnManager
import com.allion.skyray.ui.screens.AddConfigScreen
import com.allion.skyray.ui.screens.HomeScreen
import com.allion.skyray.ui.screens.ServersScreen
import com.allion.skyray.ui.screens.SettingsScreen
import com.allion.skyray.ui.theme.SkyRayTheme

class MainActivity : ComponentActivity() {
    private lateinit var vpnManager: VpnManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        vpnManager = VpnManager(this)
        val store = ProfileStore.get(this)
        // Deferred past the first frame: starting the ads SDK (it preloads a
        // video surface for the rewarded creative) while the window is still
        // being set up can leave that surface painted over the whole
        // Activity as a black layer on some devices/emulators.
        window.decorView.post { AdsManager.start(this) }

        setContent {
            val navController = rememberNavController()
            val profilesViewModel: ProfilesViewModel = viewModel(factory = object : androidx.lifecycle.ViewModelProvider.Factory {
                override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
                    @Suppress("UNCHECKED_CAST")
                    return ProfilesViewModel(store) as T
                }
            })
            val vpnPermissionLauncher = rememberVpnPermissionLauncher(vpnManager, profilesViewModel)

            SkyRayTheme {
                NavHost(
                    navController = navController,
                    startDestination = "home",
                    modifier = androidx.compose.ui.Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBars),
                ) {
                    composable("home") {
                        HomeScreen(
                            vpnManager = vpnManager,
                            profilesViewModel = profilesViewModel,
                            vpnPermissionLauncher = vpnPermissionLauncher,
                            onAddConfig = { navController.navigate("add") },
                            onServers = { navController.navigate("servers") },
                            onSettings = { navController.navigate("settings") },
                        )
                    }
                    composable("servers") {
                        ServersScreen(
                            profilesViewModel = profilesViewModel,
                            vpnManager = vpnManager,
                            onBack = { navController.popBackStack() },
                            onAddConfig = { navController.navigate("add") },
                        )
                    }
                    composable("add") {
                        AddConfigScreen(
                            profilesViewModel = profilesViewModel,
                            vpnManager = vpnManager,
                            vpnPermissionLauncher = vpnPermissionLauncher,
                            onDone = { navController.popBackStack("home", inclusive = false) },
                        )
                    }
                    composable("settings") {
                        SettingsScreen(vpnManager = vpnManager, profilesViewModel = profilesViewModel, onClose = { navController.popBackStack() })
                    }
                }
            }
        }

        intent?.let { handleIntent(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    /** skyray://connect, skyray://disconnect, skyray://add?url=<link> */
    private fun handleIntent(intent: Intent) {
        val uri = intent.data ?: return
        if (uri.scheme != "skyray") return
        when (uri.host?.lowercase()) {
            "disconnect" -> vpnManager.disconnect()
            "add" -> uri.getQueryParameter("url")?.let { link ->
                ShareLinkParser.parse(link).profiles.firstOrNull()?.let {
                    ProfileStore.get(this).let { store ->
                        val profiles = store.loadProfiles() + it
                        store.saveProfiles(profiles)
                    }
                }
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun rememberVpnPermissionLauncher(
    vpnManager: VpnManager,
    profilesViewModel: ProfilesViewModel,
) = androidx.activity.compose.rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
    if (result.resultCode == android.app.Activity.RESULT_OK) {
        val settings = vpnManager.settings
        profilesViewModel.selectedProfile(settings)?.let { vpnManager.startService(it) }
    }
}
