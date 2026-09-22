package tw.speedalert

import android.Manifest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.viewmodel.compose.viewModel
import tw.speedalert.ui.ContentScreen
import tw.speedalert.ui.SpeedAlertTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            SpeedAlertTheme {
                val vm: AppViewModel = viewModel()
                ContentScreen(vm)
            }
        }
    }
}
