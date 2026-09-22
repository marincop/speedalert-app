package tw.speedalert.location

import android.location.Location
import kotlinx.coroutines.flow.MutableStateFlow

/** Single source of GPS fixes, shared between the service and the UI/VM. */
object LocationBus {
    val location = MutableStateFlow<Location?>(null)
}
