package ir.boum.bolttube

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import ir.boum.bolttube.ui.theme.BoltTubeTheme

class MainActivity : ComponentActivity() {

    private val viewModel by viewModels<MainViewModel>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            BoltTubeTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    BoltTubeScreen(viewModel = viewModel)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BoltTubeScreen(viewModel: MainViewModel) {
    val state by remember { derivedStateOf { viewModel.uiState } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = "BoltTube Bridge") },
            )
        },
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Mac downloads the video with yt-dlp. Your phone only browses formats, starts the job, and plays the result.",
                    style = MaterialTheme.typography.bodyLarge,
                )
            }

            item {
                ConnectionCard(
                    state = state,
                    onServerUrlChanged = viewModel::onServerUrlChanged,
                    onUrlChanged = viewModel::onUrlChanged,
                    onSave = viewModel::saveInputs,
                    onResolve = viewModel::resolveFormats,
                    isBusy = state.status == BridgeStatus.Resolving || state.status == BridgeStatus.Downloading,
                )
            }

            if (state.title.isNotBlank()) {
                item {
                    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                text = "Resolved Video",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = state.title,
                                style = MaterialTheme.typography.bodyLarge,
                            )
                        }
                    }
                }
            }

            if (state.formats.isNotEmpty()) {
                item {
                    FormatPicker(
                        formats = state.formats,
                        selectedFormatId = state.selectedFormatId,
                        onSelect = viewModel::selectFormat,
                    )
                }

                item {
                    Button(
                        onClick = viewModel::startDownloadOnMac,
                        enabled = state.url.isNotBlank() && state.status != BridgeStatus.Downloading,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        if (state.status == BridgeStatus.Downloading) {
                            CircularProgressIndicator(
                                modifier = Modifier
                                    .height(18.dp)
                                    .width(18.dp),
                                strokeWidth = 2.dp,
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Downloading on Mac...")
                        } else {
                            Text("Download On Mac")
                        }
                    }
                }
            }

            item {
                StatusCard(state = state)
            }

            item {
                LibraryHeader(
                    onRefresh = viewModel::refreshLibrary,
                    isRefreshing = state.status == BridgeStatus.Refreshing,
                )
            }

            if (state.currentStreamUrl.isNotBlank()) {
                item {
                    PlayerCard(streamUrl = state.currentStreamUrl)
                }
            }

            if (state.library.isEmpty()) {
                item {
                    EmptyLibraryCard()
                }
            } else {
                items(state.library, key = { it.id }) { item ->
                    LibraryItemCard(
                        item = item,
                        onPlay = { viewModel.playItem(item) },
                    )
                }
            }

            item {
                Spacer(modifier = Modifier.height(12.dp))
            }
        }
    }
}

@Composable
private fun ConnectionCard(
    state: BridgeUiState,
    onServerUrlChanged: (String) -> Unit,
    onUrlChanged: (String) -> Unit,
    onSave: () -> Unit,
    onResolve: () -> Unit,
    isBusy: Boolean,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Bridge",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )

            OutlinedTextField(
                value = state.serverUrl,
                onValueChange = onServerUrlChanged,
                label = { Text("Mac Server URL") },
                placeholder = { Text("http://10.0.2.2:9864") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = state.url,
                onValueChange = onUrlChanged,
                label = { Text("YouTube URL") },
                placeholder = { Text("https://www.youtube.com/watch?v=...") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedButton(
                    onClick = onSave,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Save")
                }

                Button(
                    onClick = onResolve,
                    enabled = state.url.isNotBlank() && !isBusy,
                    modifier = Modifier.weight(1f),
                ) {
                    if (state.status == BridgeStatus.Resolving) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .height(18.dp)
                                .width(18.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text("Resolving...")
                    } else {
                        Text("Load Qualities")
                    }
                }
            }

            if (state.savedMessage.isNotBlank()) {
                Text(
                    text = state.savedMessage,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

@Composable
private fun FormatPicker(
    formats: List<RemoteFormat>,
    selectedFormatId: String,
    onSelect: (String) -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Qualities",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )

            formats.forEach { format ->
                FilterChip(
                    selected = selectedFormatId == format.id,
                    onClick = { onSelect(format.id) },
                    label = {
                        Column {
                            Text(text = format.title)
                            Text(
                                text = format.details,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun StatusCard(state: BridgeUiState) {
    val clipboardManager = LocalClipboardManager.current
    val tone = when (state.status) {
        BridgeStatus.Failed -> MaterialTheme.colorScheme.errorContainer
        BridgeStatus.Downloading, BridgeStatus.Resolving, BridgeStatus.Refreshing -> MaterialTheme.colorScheme.secondaryContainer
        BridgeStatus.Idle -> MaterialTheme.colorScheme.surfaceVariant
    }

    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(tone)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "Status: ${state.status.name}",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            if (state.message.isNotBlank()) {
                Text(
                    text = state.message,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            if (state.status == BridgeStatus.Failed && state.message.isNotBlank()) {
                OutlinedButton(
                    onClick = { clipboardManager.setText(AnnotatedString(state.message)) },
                ) {
                    Text("Copy Error")
                }
            }
        }
    }
}

@Composable
private fun LibraryHeader(
    onRefresh: () -> Unit,
    isRefreshing: Boolean,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HorizontalDivider()
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = "Mac Library",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
            OutlinedButton(onClick = onRefresh, enabled = !isRefreshing) {
                if (isRefreshing) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .height(18.dp)
                            .width(18.dp),
                        strokeWidth = 2.dp,
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Text("Refreshing...")
                } else {
                    Text("Refresh")
                }
            }
        }
    }
}

@Composable
private fun PlayerCard(streamUrl: String) {
    val context = LocalContext.current
    val exoPlayer = remember(context) {
        ExoPlayer.Builder(context).build().apply {
            playWhenReady = true
        }
    }

    LaunchedEffect(streamUrl) {
        exoPlayer.setMediaItem(MediaItem.fromUri(streamUrl))
        exoPlayer.prepare()
    }

    DisposableEffect(Unit) {
        onDispose {
            exoPlayer.release()
        }
    }

    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Now Playing",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(220.dp)
                    .background(
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        shape = RoundedCornerShape(18.dp),
                    ),
            ) {
                AndroidView(
                    factory = { viewContext ->
                        PlayerView(viewContext).apply {
                            player = exoPlayer
                            useController = true
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }
            Text(
                text = streamUrl,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun EmptyLibraryCard() {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "No videos yet",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Resolve a link, choose a quality, and download it on the Mac. The finished files will show up here for playback.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun LibraryItemCard(
    item: MediaSummary,
    onPlay: () -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = item.fileName,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "${item.size} • ${item.createdAt}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(
                onClick = onPlay,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Play On Phone")
            }
        }
    }
}
