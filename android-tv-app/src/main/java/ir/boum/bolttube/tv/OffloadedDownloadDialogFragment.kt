package ir.boum.bolttube.tv

import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.os.bundleOf
import androidx.core.content.ContextCompat
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.activityViewModels
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class OffloadedDownloadDialogFragment : DialogFragment() {

    private val viewModel: TvViewModel by activityViewModels()
    private val repository = MediaRepository()

    private lateinit var thumbnailView: ImageView
    private lateinit var titleView: TextView
    private lateinit var statusView: TextView
    private lateinit var spinnerView: ProgressBar
    private lateinit var progressBar: ProgressBar
    private lateinit var progressPercentView: TextView
    private lateinit var progressContainer: View
    private lateinit var qualityList: RecyclerView
    private lateinit var startButton: View
    private lateinit var cancelButton: View

    private val qualityAdapter: TvQualityAdapter by lazy(LazyThreadSafetyMode.NONE) {
        TvQualityAdapter { format ->
            selectedFormatId = format.id
            qualityAdapter.submit(formats, selectedFormatId)
            updateButtons()
            startButton.post { startButton.requestFocus() }
        }
    }

    private var formats: List<RemoteFormat> = emptyList()
    private var selectedFormatId: String = ""
    private var resolvedClient: String = ""
    private var pollJob: Job? = null
    private var resolveJob: Job? = null
    private var isResolving = false
    private var isDownloading = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setStyle(STYLE_NO_TITLE, android.R.style.Theme_DeviceDefault_Light_Dialog_NoActionBar)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        return inflater.inflate(R.layout.dialog_tv_offloaded_download, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        thumbnailView = view.findViewById(R.id.downloadDialogThumbnail)
        titleView = view.findViewById(R.id.downloadDialogTitle)
        statusView = view.findViewById(R.id.downloadDialogStatus)
        spinnerView = view.findViewById(R.id.downloadDialogSpinner)
        progressBar = view.findViewById(R.id.downloadDialogProgress)
        progressPercentView = view.findViewById(R.id.downloadDialogPercent)
        progressContainer = view.findViewById(R.id.downloadDialogProgressContainer)
        qualityList = view.findViewById<RecyclerView>(R.id.downloadDialogQualityList)
        qualityList.layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
        qualityList.adapter = qualityAdapter
        
        startButton = view.findViewById<View>(R.id.downloadDialogStart)
        cancelButton = view.findViewById<View>(R.id.downloadDialogCancel)
        
        startButton.setOnClickListener { startDownload() }
        cancelButton.setOnClickListener { dismissAllowingStateLoss() }

        listOf(startButton, cancelButton).forEach { button ->
            button.setOnFocusChangeListener { v, hasFocus ->
                v.animate()
                    .scaleX(if (hasFocus) 1.04f else 1f)
                    .scaleY(if (hasFocus) 1.04f else 1f)
                    .setDuration(150)
                    .start()
            }
        }

        titleView.text = requireArguments().getString(ARG_TITLE).orEmpty()
        val thumbnailUrl = requireArguments().getString(ARG_THUMBNAIL_URL).orEmpty()
        if (thumbnailUrl.isNotBlank()) {
            Glide.with(this).load(thumbnailUrl).centerCrop().into(thumbnailView)
        }

        updateStatus("Loading available qualities...")
        updateButtons()
        resolveFormats()
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        dialog?.window?.setLayout(
            (resources.displayMetrics.widthPixels * 0.72f).toInt(),
            WindowManager.LayoutParams.WRAP_CONTENT,
        )
    }

    override fun onDestroyView() {
        pollJob?.cancel()
        resolveJob?.cancel()
        super.onDestroyView()
    }

    override fun onDestroy() {
        repository.close()
        super.onDestroy()
    }

    private fun resolveFormats() {
        resolveJob?.cancel()
        isResolving = true
        updateButtons()
        val serverUrl = viewModel.uiState.value.serverUrl
        val mediaId = requireArguments().getString(ARG_MEDIA_ID).orEmpty()
        resolveJob = viewLifecycleOwner.lifecycleScope.launch {
            val response = runCatching {
                repository.resolveOffloaded(serverUrl, mediaId)
            }.recoverCatching {
                delay(1200)
                repository.resolveOffloaded(serverUrl, mediaId)
            }
            response.onSuccess { response ->
                isResolving = false
                formats = response.formats
                selectedFormatId = response.formats.lastOrNull()?.id.orEmpty()
                resolvedClient = response.resolvedClient
                titleView.text = response.title.ifBlank { titleView.text }
                if (response.thumbnailUrl.isNotBlank()) {
                    Glide.with(this@OffloadedDownloadDialogFragment)
                        .load(viewModel.absoluteMediaUrl(response.thumbnailUrl))
                        .centerCrop()
                        .into(thumbnailView)
                }
                qualityAdapter.submit(formats, selectedFormatId)
                updateStatus(if (formats.isEmpty()) "No qualities found." else "Choose a quality and start download.")
                updateButtons()
                qualityList.post { qualityList.getChildAt(formats.lastIndex.coerceAtLeast(0))?.requestFocus() }
            }.onFailure { error ->
                isResolving = false
                updateStatus(error.message ?: "Could not load qualities.")
                updateButtons()
            }
        }
    }

    private fun startDownload() {
        if (selectedFormatId.isBlank() || isDownloading) return
        val serverUrl = viewModel.uiState.value.serverUrl
        val mediaId = requireArguments().getString(ARG_MEDIA_ID).orEmpty()
        isDownloading = true
        updateStatus("Starting download...")
        updateButtons()
        viewLifecycleOwner.lifecycleScope.launch {
            runCatching {
                repository.startOffloadedDownload(serverUrl, mediaId, selectedFormatId, resolvedClient)
            }.onSuccess {
                startPolling(mediaId)
            }.onFailure { error ->
                isDownloading = false
                updateStatus(error.message ?: "Could not start download.")
                updateButtons()
            }
        }
    }

    private fun startPolling(mediaId: String) {
        pollJob?.cancel()
        pollJob = viewLifecycleOwner.lifecycleScope.launch {
            val serverUrl = viewModel.uiState.value.serverUrl
            while (true) {
                val result = runCatching { repository.fetchOffloadedDownloadStatus(serverUrl, mediaId) }
                val status = result.getOrElse { error ->
                    isDownloading = false
                    updateStatus(error.message ?: "Download status failed.")
                    updateButtons()
                    return@launch
                }
                renderStatus(status)
                when (status.status) {
                    "completed" -> {
                        isDownloading = false
                        viewModel.refreshAll()
                        val streamUrl = status.streamUrl.ifBlank { viewModel.absoluteMediaUrl("/media/$mediaId") }
                        startActivity(
                            Intent(requireContext(), VideoPlayerActivity::class.java)
                                .putExtra(VideoPlayerActivity.EXTRA_STREAM_URL, streamUrl)
                                .putExtra(VideoPlayerActivity.EXTRA_TITLE, status.title.ifBlank { titleView.text.toString() })
                                .putExtra(VideoPlayerActivity.EXTRA_ID, mediaId),
                        )
                        delay(300)
                        dismissAllowingStateLoss()
                        return@launch
                    }
                    "failed" -> {
                        isDownloading = false
                        updateButtons()
                        return@launch
                    }
                }
                delay(700)
            }
        }
    }

    private fun renderStatus(status: OffloadedDownloadStatus) {
        val title = status.title.ifBlank { titleView.text.toString() }
        titleView.text = title
        val percent = (status.fraction * 100).toInt().coerceIn(0, 100)
        progressBar.progress = percent
        progressPercentView.text = "$percent%"
        when (status.status) {
            "queued" -> updateStatus("Queued...")
            "resolving" -> updateStatus("Resolving qualities...")
            "downloading" -> updateStatus(
                buildString {
                    append("Downloading")
                    if (status.speedBytesPerSecond > 0.0) {
                        append("  ")
                        append(formatSpeed(status.speedBytesPerSecond))
                        append("/s")
                    }
                },
            )
            "merging" -> updateStatus("Merging final file...")
            "completed" -> updateStatus("Download complete")
            "failed" -> updateStatus(status.error.ifBlank { "Download failed." })
            else -> updateStatus("Preparing download...")
        }
        spinnerView.visibility = if (status.status in setOf("queued", "resolving")) View.VISIBLE else View.GONE
        val showProgress = status.status in setOf("downloading", "merging", "completed")
        progressContainer.visibility = if (showProgress) View.VISIBLE else View.GONE
        progressBar.visibility = if (showProgress) View.VISIBLE else View.INVISIBLE
        progressPercentView.visibility = if (showProgress) View.VISIBLE else View.INVISIBLE
        updateButtons()
    }

    private fun updateStatus(message: String) {
        statusView.text = message
        spinnerView.visibility = if (isResolving || (isDownloading && progressBar.progress == 0)) View.VISIBLE else View.GONE
    }

    private fun updateButtons() {
        startButton.isEnabled = !isResolving && !isDownloading && selectedFormatId.isNotBlank()
        
        // Update button texts if they are LinearLayouts with TextViews
        cancelButton.findViewById<TextView>(R.id.downloadDialogCancelText)?.let {
            it.text = if (isDownloading) "Close" else "Cancel"
        }
        startButton.findViewById<TextView>(R.id.downloadDialogStartText)?.let {
            it.text = if (isDownloading) "Downloading..." else "Start Download"
        }

        if (!isResolving && !(isDownloading && progressBar.progress == 0)) {
            spinnerView.visibility = View.GONE
        }
    }

    private fun formatSpeed(bytesPerSecond: Double): String {
        return when {
            bytesPerSecond >= 1024 * 1024 -> String.format("%.1f MB", bytesPerSecond / (1024 * 1024))
            bytesPerSecond >= 1024 -> String.format("%.0f KB", bytesPerSecond / 1024)
            else -> String.format("%.0f B", bytesPerSecond)
        }
    }

    companion object {
        private const val ARG_MEDIA_ID = "media_id"
        private const val ARG_TITLE = "title"
        private const val ARG_THUMBNAIL_URL = "thumbnail_url"

        fun newInstance(mediaId: String, title: String, thumbnailUrl: String): OffloadedDownloadDialogFragment {
            return OffloadedDownloadDialogFragment().apply {
                arguments = bundleOf(
                    ARG_MEDIA_ID to mediaId,
                    ARG_TITLE to title,
                    ARG_THUMBNAIL_URL to thumbnailUrl,
                )
            }
        }
    }
}

private class TvQualityAdapter(
    private val onClick: (RemoteFormat) -> Unit,
) : RecyclerView.Adapter<TvQualityAdapter.QualityViewHolder>() {
    private val items = mutableListOf<RemoteFormat>()
    private var selectedId: String = ""

    fun submit(newItems: List<RemoteFormat>, selectedId: String) {
        items.clear()
        items.addAll(newItems)
        this.selectedId = selectedId
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): QualityViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_tv_quality_option, parent, false)
        return QualityViewHolder(view, onClick)
    }

    override fun onBindViewHolder(holder: QualityViewHolder, position: Int) {
        holder.bind(
            item = items[position],
            selected = items[position].id == selectedId,
            isFirst = position == 0,
            isLast = position == items.lastIndex,
        )
    }

    override fun getItemCount(): Int = items.size

    class QualityViewHolder(
        itemView: View,
        private val onClick: (RemoteFormat) -> Unit,
    ) : RecyclerView.ViewHolder(itemView) {
        private val titleView = itemView.findViewById<TextView>(R.id.qualityOptionTitle)
        private val subtitleView = itemView.findViewById<TextView>(R.id.qualityOptionSubtitle)
        private var boundItem: RemoteFormat? = null
        private var selected = false

        init {
            itemView.setOnClickListener { boundItem?.let(onClick) }
            itemView.setOnFocusChangeListener { view, hasFocus ->
                view.animate()
                    .scaleX(if (hasFocus) 1.06f else 1f)
                    .scaleY(if (hasFocus) 1.06f else 1f)
                    .translationZ(if (hasFocus) 18f else 0f)
                    .setDuration(140)
                    .start()
                applyState(hasFocus)
            }
        }

        fun bind(item: RemoteFormat, selected: Boolean, isFirst: Boolean, isLast: Boolean) {
            boundItem = item
            this.selected = selected
            (itemView.layoutParams as? RecyclerView.LayoutParams)?.let { params ->
                params.marginStart = if (isFirst) dp(itemView, 16) else 0
                params.marginEnd = if (isLast) dp(itemView, 16) else dp(itemView, 8)
                itemView.layoutParams = params
            }
            titleView.text = item.title
            val subtitle = item.filesize.trim()
            if (subtitle.isNotEmpty()) {
                subtitleView.text = subtitle
                subtitleView.visibility = View.VISIBLE
            } else {
                subtitleView.text = ""
                subtitleView.visibility = View.GONE
            }
            itemView.alpha = if (selected) 1f else 0.96f
            applyState(itemView.isFocused)
        }

        private fun applyState(hasFocus: Boolean) {
            val backgroundRes = when {
                selected -> R.drawable.bg_tv_quality_option_selected
                hasFocus -> R.drawable.bg_tv_quality_option_focused
                else -> R.drawable.bg_tv_quality_option_idle
            }
            val primaryColor = android.R.color.white
            val secondaryColor = if (selected || hasFocus) android.R.color.white else R.color.slate_400
            
            itemView.background = ContextCompat.getDrawable(itemView.context, backgroundRes)
            titleView.setTextColor(ContextCompat.getColor(itemView.context, primaryColor))
            subtitleView.setTextColor(ContextCompat.getColor(itemView.context, secondaryColor))
        }

        private fun dp(view: View, value: Int): Int {
            return (value * view.resources.displayMetrics.density).toInt()
        }
    }
}
