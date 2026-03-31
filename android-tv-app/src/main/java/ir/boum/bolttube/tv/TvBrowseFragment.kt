package ir.boum.bolttube.tv

import android.content.Intent
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.fragment.app.activityViewModels
import androidx.leanback.app.BackgroundManager
import androidx.leanback.app.RowsSupportFragment
import androidx.leanback.widget.ArrayObjectAdapter
import androidx.leanback.widget.HeaderItem
import androidx.leanback.widget.ImageCardView
import androidx.leanback.widget.ListRow
import androidx.leanback.widget.ListRowPresenter
import androidx.leanback.widget.OnItemViewClickedListener
import androidx.leanback.widget.Presenter
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.bumptech.glide.Glide
import kotlinx.coroutines.launch

class TvBrowseFragment : RowsSupportFragment() {

    private val viewModel: TvViewModel by activityViewModels()
    private val rowsAdapter = ArrayObjectAdapter(ListRowPresenter())
    private lateinit var backgroundManager: BackgroundManager

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        backgroundManager = BackgroundManager.getInstance(requireActivity()).apply {
            attach(requireActivity().window)
            color = ContextCompat.getColor(requireContext(), R.color.tv_background)
        }

        adapter = rowsAdapter

        onItemViewClickedListener = OnItemViewClickedListener { _, item, _, _ ->
            when (item) {
                is ActionItem -> handleAction(item.id)
                is VideoItem -> playVideo(item)
            }
        }

        observeState()
    }

    fun openServerDialog() {
        ServerConfigDialogFragment.newInstance(viewModel.uiState.value.serverUrl)
            .show(parentFragmentManager, "server_config")
    }

    fun submitServerUrl(url: String) {
        viewModel.saveServerUrl(url)
    }

    private fun observeState() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiState.collect { state ->
                    buildRows(state)
                }
            }
        }
    }

    private fun buildRows(state: TvUiState) {
        rowsAdapter.clear()

        val actionPresenter = ActionCardPresenter()
        val actionAdapter = ArrayObjectAdapter(actionPresenter).apply {
            add(ActionItem("refresh", getString(R.string.action_refresh), state.message.ifBlank { "Pull the latest list from your Mac app" }))
            add(ActionItem("server", getString(R.string.action_server), state.serverUrl))
            if (state.error.isNotBlank()) {
                add(ActionItem("retry", getString(R.string.action_retry), state.error))
            }
        }
        rowsAdapter.add(ListRow(HeaderItem(0, getString(R.string.row_actions)), actionAdapter))

        val videoPresenter = VideoCardPresenter()
        val videoAdapter = ArrayObjectAdapter(videoPresenter)
        state.library.forEach { item ->
            videoAdapter.add(
                VideoItem(
                    id = item.id,
                    title = item.fileName.removeSuffix(".mp4"),
                    subtitle = item.size,
                    thumbnailUrl = item.thumbnailUrl,
                    streamUrl = viewModel.absoluteMediaUrl(item.streamUrl),
                ),
            )
        }
        if (state.library.isEmpty()) {
            videoAdapter.add(
                ActionItem(
                    id = "server",
                    title = getString(R.string.empty_library),
                    subtitle = state.error.ifBlank { state.serverUrl },
                ),
            )
        }

        rowsAdapter.add(ListRow(HeaderItem(1, getString(R.string.row_library)), videoAdapter))
    }

    private fun handleAction(actionId: String) {
        when (actionId) {
            "refresh", "retry" -> viewModel.refreshLibrary()
            "server" -> openServerDialog()
        }
    }

    private fun playVideo(item: VideoItem) {
        startActivity(
            Intent(requireContext(), VideoPlayerActivity::class.java)
                .putExtra(VideoPlayerActivity.EXTRA_STREAM_URL, item.streamUrl)
                .putExtra(VideoPlayerActivity.EXTRA_TITLE, item.title),
        )
    }
}

private class ActionCardPresenter : Presenter() {
    private data class ActionCardViews(
        val container: LinearLayout,
        val titleView: TextView,
        val subtitleView: TextView,
    )

    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val context = parent.context
        val titleView = TextView(context).apply {
            setTextColor(ContextCompat.getColor(context, R.color.tv_text))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.END
        }
        val subtitleView = TextView(context).apply {
            setTextColor(ContextCompat.getColor(context, R.color.tv_muted))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
        }
        val container = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            isFocusable = true
            isFocusableInTouchMode = true
            layoutParams = ViewGroup.MarginLayoutParams(dp(context, 420), dp(context, 132)).apply {
                rightMargin = dp(context, 24)
            }
            setPadding(dp(context, 28), dp(context, 22), dp(context, 28), dp(context, 22))
            background = actionBackground(context, focused = false)
            addView(titleView)
            addView(subtitleView)
            setOnFocusChangeListener { view, hasFocus ->
                view.background = actionBackground(context, focused = hasFocus)
                view.animate()
                    .scaleX(if (hasFocus) 1.04f else 1f)
                    .scaleY(if (hasFocus) 1.04f else 1f)
                    .setDuration(140)
                    .start()
            }
        }
        return ViewHolder(ActionCardViews(container, titleView, subtitleView).container)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any?) {
        val action = item as ActionItem
        val container = viewHolder.view as LinearLayout
        val titleView = container.getChildAt(0) as TextView
        val subtitleView = container.getChildAt(1) as TextView
        titleView.text = action.title
        subtitleView.text = action.subtitle
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) = Unit

    private fun actionBackground(context: android.content.Context, focused: Boolean): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(context, 18).toFloat()
            setColor(
                if (focused) {
                    ContextCompat.getColor(context, R.color.tv_surface_alt)
                } else {
                    ContextCompat.getColor(context, R.color.tv_surface)
                }
            )
            setStroke(
                dp(context, if (focused) 2 else 1),
                ContextCompat.getColor(context, if (focused) R.color.tv_focus else R.color.tv_surface_alt),
            )
        }
    }
}

private class VideoCardPresenter : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val cardView = ImageCardView(parent.context).apply {
            isFocusable = true
            isFocusableInTouchMode = true
            setMainImageDimensions(560, 315)
            setInfoAreaBackgroundColor(ContextCompat.getColor(context, R.color.tv_surface))
            setBackgroundColor(ContextCompat.getColor(context, R.color.tv_surface_alt))
            mainImageView?.scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
            setOnFocusChangeListener { view, hasFocus ->
                view.animate()
                    .scaleX(if (hasFocus) 1.06f else 1f)
                    .scaleY(if (hasFocus) 1.06f else 1f)
                    .setDuration(160)
                    .start()
            }
        }
        (cardView.layoutParams as? ViewGroup.MarginLayoutParams)?.rightMargin = dp(parent.context, 28)
        return ViewHolder(cardView)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any?) {
        val cardView = viewHolder.view as ImageCardView
        when (item) {
            is VideoItem -> {
                cardView.titleText = item.title
                cardView.contentText = item.subtitle
                loadImage(cardView, item.thumbnailUrl)
            }
            is ActionItem -> {
                cardView.titleText = item.title
                cardView.contentText = item.subtitle
                cardView.mainImage = null
            }
        }
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {
        val cardView = viewHolder.view as ImageCardView
        cardView.mainImageView?.let { imageView ->
            Glide.with(cardView.context).clear(imageView)
        }
    }

    private fun loadImage(cardView: ImageCardView, thumbnailUrl: String?) {
        if (thumbnailUrl.isNullOrBlank()) {
            cardView.mainImage = fallback(cardView)
            return
        }

        Glide.with(cardView.context)
            .load(thumbnailUrl)
            .centerCrop()
            .error(fallback(cardView))
            .into(requireNotNull(cardView.mainImageView))
    }

    private fun fallback(cardView: ImageCardView): Drawable? {
        return ContextCompat.getDrawable(cardView.context, R.drawable.ic_tv_launcher)
    }
}

private fun dp(context: android.content.Context, value: Int): Int {
    return TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP,
        value.toFloat(),
        context.resources.displayMetrics,
    ).toInt()
}
