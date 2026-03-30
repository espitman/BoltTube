import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow

class MainActivity : ComponentActivity() {

    private val viewModel by viewModels<MainViewModel>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            BoltTubeTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
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
    val scrollState = rememberScrollState()

    Scaffold(
        topBar = {
            LargeTopAppBar(
                title = { 
                    Column {
                        Text(
                            text = "BoltTube Bridge",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = "Remote Media Controller",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary.opacity(0.7f)
                        )
                    }
                },
                colors = TopAppBarDefaults.largeTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    scrolledContainerColor = MaterialTheme.colorScheme.surfaceVariant.opacity(0.5f)
                )
            )
        },
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            item {
                Text(
                    text = "Control your Mac downloads and browse your library from anywhere on your local network.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
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
                    VideoPreviewCard(title = state.title)
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
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp),
                        shape = RoundedCornerShape(16.dp)
                    ) {
                        if (state.status == BridgeStatus.Downloading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                strokeWidth = 3.dp,
                                color = MaterialTheme.colorScheme.onPrimary
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Importing on Mac...")
                        } else {
                            Icon(Icons.Default.PlayArrow, contentDescription = null)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Start Import Process")
                        }
                    }
                }
            }

            item {
                StatusBadge(state = state)
            }

            item {
                LibrarySection(
                    items = state.library,
                    onRefresh = viewModel::refreshLibrary,
                    isRefreshing = state.status == BridgeStatus.Refreshing,
                    onPlay = { viewModel.playItem(it) },
                    currentStreamUrl = state.currentStreamUrl
                )
            }

            item { Spacer(modifier = Modifier.height(32.dp)) }
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
    val clipboardManager = LocalClipboardManager.current

    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.opacity(0.4f),
        shape = RoundedCornerShape(28.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "Link Import",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = { 
                    clipboardManager.getText()?.let { onUrlChanged(it.text) }
                }) {
                    Icon(Icons.Default.ContentPaste, contentDescription = "Paste")
                }
            }

            OutlinedTextField(
                value = state.serverUrl,
                onValueChange = onServerUrlChanged,
                label = { Text("Server Address") },
                placeholder = { Text("e.g. 192.168.1.5:9864") },
                singleLine = true,
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = state.url,
                onValueChange = onUrlChanged,
                label = { Text("Content URL") },
                placeholder = { Text("https://youtube.com/...") },
                singleLine = true,
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.fillMaxWidth(),
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedButton(
                    onClick = onSave,
                    modifier = Modifier.weight(1f).height(48.dp),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Text("Save")
                }

                Button(
                    onClick = onResolve,
                    enabled = state.url.isNotBlank() && !isBusy,
                    modifier = Modifier.weight(1f).height(48.dp),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    if (state.status == BridgeStatus.Resolving) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        Text("Analyze Link")
                    }
                }
            }

            if (state.savedMessage.isNotBlank()) {
                Text(
                    text = state.savedMessage,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(start = 4.dp)
                )
            }
        }
    }
}

@Composable
private fun VideoPreviewCard(title: String) {
    Surface(
        color = MaterialTheme.colorScheme.primary.opacity(0.1f),
        shape = RoundedCornerShape(24.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Target Content",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FormatPicker(
    formats: List<RemoteFormat>,
    selectedFormatId: String,
    onSelect: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = "Quality",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 4.dp)
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            formats.take(4).forEach { format ->
                FilterChip(
                    selected = selectedFormatId == format.id,
                    onClick = { onSelect(format.id) },
                    label = { Text(text = format.title.take(8)) },
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.padding(0.dp)
                )
            }
        }
    }
}

@Composable
private fun StatusBadge(state: BridgeUiState) {
    val containerColor = when (state.status) {
        BridgeStatus.Failed -> MaterialTheme.colorScheme.errorContainer
        BridgeStatus.Idle -> MaterialTheme.colorScheme.surfaceVariant
        else -> MaterialTheme.colorScheme.secondaryContainer
    }
    
    val contentColor = when(state.status) {
        BridgeStatus.Failed -> MaterialTheme.colorScheme.onErrorContainer
        BridgeStatus.Idle -> MaterialTheme.colorScheme.onSurfaceVariant
        else -> MaterialTheme.colorScheme.onSecondaryContainer
    }

    Surface(
        color = containerColor,
        contentColor = contentColor,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(Icons.Default.Info, contentDescription = null, modifier = Modifier.size(20.dp))
            Column {
                Text(
                    text = state.status.name,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold
                )
                if (state.message.isNotBlank()) {
                    Text(
                        text = state.message,
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

@Composable
private fun LibrarySection(
    items: List<MediaSummary>,
    onRefresh: () -> Unit,
    isRefreshing: Boolean,
    onPlay: (MediaSummary) -> Unit,
    currentStreamUrl: String
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "My Collection",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            IconButton(onClick = onRefresh, enabled = !isRefreshing) {
                Icon(Icons.Default.Refresh, contentDescription = "Refresh")
            }
        }

        if (currentStreamUrl.isNotBlank()) {
            PlayerCard(streamUrl = currentStreamUrl)
        }

        if (items.isEmpty()) {
            Text(
                text = "No content available. Analyze a link to start importing.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 12.dp)
            )
        } else {
            items.forEach { item ->
                LibraryItemRow(item = item, onPlay = { onPlay(item) })
                HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp), alpha = 0.5f)
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

    Surface(
        color = Color.Black,
        shape = RoundedCornerShape(24.dp),
        modifier = Modifier
            .fillMaxWidth()
            .height(240.dp)
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
}

@Composable
private fun LibraryItemRow(
    item: MediaSummary,
    onPlay: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Surface(
            color = MaterialTheme.colorScheme.primaryContainer,
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.size(48.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Default.PlayArrow, 
                    contentDescription = null, 
                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = item.fileName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = "${item.size} • ${item.createdAt}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        IconButton(onClick = onPlay) {
            Icon(Icons.Default.PlayArrow, contentDescription = "Play")
        }
    }
}

private fun Color.opacity(value: Float): Color = copy(alpha = value)
