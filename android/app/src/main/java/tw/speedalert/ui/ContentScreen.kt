package tw.speedalert.ui

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import tw.speedalert.AppViewModel
import tw.speedalert.model.EnforcementKind
import tw.speedalert.model.NearbyHit

private fun iconFor(kind: EnforcementKind): ImageVector = when (kind) {
    EnforcementKind.FIXED_SPEED, EnforcementKind.HIGHWAY_SPEED -> Icons.Filled.PhotoCamera
    EnforcementKind.INTERVAL_SPEED -> Icons.Filled.Timer
    EnforcementKind.TECH_INTERSECTION, EnforcementKind.TECH_OTHER -> Icons.Filled.Traffic
    EnforcementKind.ACCIDENT_SEGMENT -> Icons.Filled.Warning
}

private fun colorFor(kind: EnforcementKind): Color = when (kind) {
    EnforcementKind.FIXED_SPEED, EnforcementKind.HIGHWAY_SPEED -> Color(0xFFEF4444)
    EnforcementKind.INTERVAL_SPEED -> Color(0xFFF59E0B)
    EnforcementKind.TECH_INTERSECTION, EnforcementKind.TECH_OTHER -> Color(0xFF3B82F6)
    EnforcementKind.ACCIDENT_SEGMENT -> Color(0xFFEAB308)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContentScreen(vm: AppViewModel) {
    val context = LocalContext.current
    val driving by vm.driving.collectAsState()
    val speed by vm.speed.collectAsState()
    val nearest by vm.nearest.collectAsState()
    val lastAlert by vm.lastAlert.collectAsState()
    var showSettings by remember { mutableStateOf(false) }

    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { }
    LaunchedEffect(Unit) {
        permLauncher.launch(
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.POST_NOTIFICATIONS)
        )
    }

    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(BgTop, BgBot)))) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            TopBar(vm, onSettings = { showSettings = true })
            SpeedRing(speed, driving)
            nearest.firstOrNull()?.let { NextAlertCard(it) }
            DriveButton(driving) { vm.toggleDriving() }
            if (lastAlert.isNotEmpty()) LastSpoken(lastAlert)
            NearbySection(driving, nearest)
            Text(
                "資料來源：政府資料開放平臺。僅供提醒參考，實際以現場標誌為準。",
                color = Color(0x66FFFFFF),
                fontSize = 11.sp,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp)
            )
        }
    }

    if (showSettings) {
        SettingsSheet(vm, onDismiss = { showSettings = false })
    }
}

@Composable
private fun TopBar(vm: AppViewModel, onSettings: () -> Unit) {
    val ok = vm.store.loadError == null && vm.store.items.isNotEmpty()
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("測速提醒", fontWeight = FontWeight.Bold, fontSize = 20.sp, color = Color.White)
            Text(
                "全台測速 · 科技執法 · 肇事路段",
                fontSize = 11.sp, color = Color(0x99FFFFFF)
            )
        }
        Row(
            Modifier.clip(CircleShape)
                .background((if (ok) Color(0xFF22C55E) else Color(0xFFEF4444)).copy(alpha = 0.18f))
                .padding(horizontal = 10.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                if (ok) Icons.Filled.CheckCircle else Icons.Filled.Warning,
                contentDescription = null, tint = if (ok) Color(0xFF22C55E) else Color(0xFFEF4444),
                modifier = Modifier.size(14.dp)
            )
            Text(
                if (ok) "${vm.store.items.size} 點" else "無資料",
                fontSize = 11.sp, color = if (ok) Color(0xFF22C55E) else Color(0xFFEF4444)
            )
        }
        Spacer(Modifier.width(8.dp))
        IconButton(
            onClick = onSettings,
            modifier = Modifier.clip(CircleShape).background(Color(0x14FFFFFF))
        ) {
            Icon(Icons.Filled.Settings, contentDescription = "設定", tint = Color.White)
        }
    }
}

@Composable
private fun SpeedRing(speed: Double, driving: Boolean) {
    Box(Modifier.fillMaxWidth().padding(top = 6.dp), contentAlignment = Alignment.Center) {
        val ring = if (driving) Color(0xFF22C55E).copy(alpha = 0.5f) else Color(0x1AFFFFFF)
        Canvas(Modifier.size(210.dp)) {
            drawCircle(color = ring, style = androidx.compose.ui.graphics.drawscope.Stroke(width = 10f))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                String.format("%.0f", speed),
                fontSize = 76.sp, fontWeight = FontWeight.Black, color = Color.White
            )
            Text("km/h", fontSize = 15.sp, color = Color(0x99FFFFFF))
        }
    }
}

@Composable
private fun NextAlertCard(hit: NearbyHit) {
    val tint = colorFor(hit.item.kind)
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0x14FFFFFF))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Box(
            Modifier.size(46.dp).clip(CircleShape).background(tint.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center
        ) { Icon(iconFor(hit.item.kind), contentDescription = null, tint = tint) }
        Column(Modifier.weight(1f)) {
            Text(hit.item.kind.displayName, fontWeight = FontWeight.Bold, color = Color.White)
            Text(
                hit.item.label, fontSize = 12.sp, color = Color(0x99FFFFFF),
                maxLines = 1
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            Text("${hit.distance.toInt()} m", fontWeight = FontWeight.Bold, color = Color.White)
            hit.item.limit?.let { SpeedLimitBadge(it, 38) }
        }
    }
}

@Composable
fun SpeedLimitBadge(limit: Int, size: Int) {
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(Color.White),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(
                color = Color(0xFFDC2626),
                style = androidx.compose.ui.graphics.drawscope.Stroke(width = size * 0.11f)
            )
        }
        Text(
            "$limit", color = Color.Black, fontWeight = FontWeight.Black,
            fontSize = (size * 0.42f).sp
        )
    }
}

@Composable
private fun DriveButton(driving: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        shape = RoundedCornerShape(18.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
        contentPadding = PaddingValues(),
        modifier = Modifier.fillMaxWidth().height(56.dp)
    ) {
        Row(
            Modifier.fillMaxSize().background(
                Brush.horizontalGradient(
                    if (driving) listOf(Color(0xFFEF4444), Color(0xFFEC4899))
                    else listOf(Color(0xFF3B82F6), Color(0xFF22D3EE))
                )
            ),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                if (driving) Icons.Filled.Stop else Icons.Filled.DirectionsCar,
                contentDescription = null, tint = Color.White
            )
            Spacer(Modifier.width(10.dp))
            Text(
                if (driving) "結束行車模式" else "開始行車模式",
                color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp
            )
        }
    }
}

@Composable
private fun LastSpoken(text: String) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
            .background(Color(0x26EAB308)).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(Icons.Filled.VolumeUp, contentDescription = null, tint = Color(0xFFEAB308))
        Text(text, color = Color(0xFFEAB308), fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
    }
}

@Composable
private fun NearbySection(driving: Boolean, hits: List<NearbyHit>) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("前方提醒點", fontWeight = FontWeight.Bold, color = Color.White)
            Spacer(Modifier.weight(1f))
            Text(
                if (driving) "行車中" else "未開始",
                fontSize = 11.sp, color = if (driving) Color(0xFF22C55E) else Color(0x88FFFFFF)
            )
        }
        if (hits.isEmpty()) {
            Text(
                if (driving) "附近暫無資料點" else "按「開始行車模式」後顯示",
                color = Color(0x99FFFFFF), fontSize = 14.sp
            )
        } else {
            for (hit in hits) {
                val tint = colorFor(hit.item.kind)
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                        .background(Color(0x0DFFFFFF)).padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        Modifier.size(34.dp).clip(CircleShape).background(tint.copy(alpha = 0.16f)),
                        contentAlignment = Alignment.Center
                    ) { Icon(iconFor(hit.item.kind), null, tint = tint, modifier = Modifier.size(18.dp)) }
                    Column(Modifier.weight(1f)) {
                        Text(hit.item.kind.displayName, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        Text(hit.item.label, color = Color(0x88FFFFFF), fontSize = 11.sp, maxLines = 1)
                    }
                    Text("${hit.distance.toInt()} m", color = Color(0x99FFFFFF), fontSize = 14.sp)
                    hit.item.limit?.let { SpeedLimitBadge(it, 30) }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsSheet(vm: AppViewModel, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState()
    var s500 by remember { mutableStateOf(true) }
    var s300 by remember { mutableStateOf(true) }
    var s100 by remember { mutableStateOf(true) }
    var s0 by remember { mutableStateOf(true) }
    var kFixed by remember { mutableStateOf(true) }
    var kInterval by remember { mutableStateOf(true) }
    var kTech by remember { mutableStateOf(true) }
    var kAccident by remember { mutableStateOf(true) }

    fun apply() {
        val stages = buildList {
            if (s500) add(500.0)
            if (s300) add(300.0)
            if (s100) add(100.0)
            if (s0) add(0.0)
        }
        vm.stages = stages.ifEmpty { listOf(500.0, 300.0, 100.0, 0.0) }
        val kinds = buildSet {
            if (kFixed) { add(EnforcementKind.FIXED_SPEED); add(EnforcementKind.HIGHWAY_SPEED) }
            if (kInterval) add(EnforcementKind.INTERVAL_SPEED)
            if (kTech) { add(EnforcementKind.TECH_INTERSECTION); add(EnforcementKind.TECH_OTHER) }
            if (kAccident) add(EnforcementKind.ACCIDENT_SEGMENT)
        }
        vm.enabledKinds = kinds
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier.padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text("設定", fontWeight = FontWeight.Bold, fontSize = 20.sp)
            Text("提醒距離（公尺）", color = Color(0x88FFFFFF), fontSize = 12.sp)
            SwitchRow("500 公尺", s500) { s500 = it; apply() }
            SwitchRow("300 公尺", s300) { s300 = it; apply() }
            SwitchRow("100 公尺", s100) { s100 = it; apply() }
            SwitchRow("0 公尺（通過）", s0) { s0 = it; apply() }
            Text("提醒種類", color = Color(0x88FFFFFF), fontSize = 12.sp)
            SwitchRow("固定式／國道測速", kFixed) { kFixed = it; apply() }
            SwitchRow("區間測速", kInterval) { kInterval = it; apply() }
            SwitchRow("路口科技執法", kTech) { kTech = it; apply() }
            SwitchRow("易肇事路段", kAccident) { kAccident = it; apply() }
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = { vm.previewVoice() }, modifier = Modifier.fillMaxWidth()) {
                Text("試聽語音")
            }
            Text(
                "資料 ${vm.store.items.size} 點 · 版本 ${vm.store.builtAt ?: "—"}",
                color = Color(0x66FFFFFF), fontSize = 12.sp
            )
        }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, Modifier.weight(1f), color = Color.White)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
