package ir.boum.bolttube.tv

import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.fragment.app.viewModels
import androidx.leanback.app.RowsSupportFragment
import androidx.leanback.app.BackgroundManager
import androidx.leanback.widget.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.launch
import android.content.Intent

class TvBrowseFragment : RowsSupportFragment() {

    val viewModel: TvViewModel by viewModels()
    private lateinit var backgroundManager: BackgroundManager
    private val rowsAdapter = ArrayObjectAdapter(ListRowPresenter().apply {
        headerPresenter = CustomHeaderPresenter()
    })

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        view.findViewById<View>(androidx.leanback.R.id.browse_title_group)?.visibility = View.GONE
        
        backgroundManager = BackgroundManager.getInstance(requireActivity()).apply {
            attach(requireActivity().window)
            setColor(ContextCompat.getColor(requireContext(), R.color.tv_background))
        }

        adapter = rowsAdapter
        
        verticalGridView.apply {
            setPadding(0, 0, 0, 0)
            clipToPadding = false
        }
        setAlignment(0)

        onItemViewClickedListener = OnItemViewClickedListener { _, item, _, _ ->
            if (item is VideoItem) {
                val intent = Intent(requireContext(), VideoPlayerActivity::class.java).apply {
                    putExtra("VIDEO_URL", item.streamUrl)
                    putExtra("VIDEO_TITLE", item.title)
                }
                startActivity(intent)
            }
        }

        observeViewModel()
    }

    private fun observeViewModel() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiState.collect { state ->
                    val videoItems = state.library.map { item ->
                        VideoItem(
                            id = item.id,
                            title = item.fileName.removeSuffix(".mp4"),
                            subtitle = item.size,
                            thumbnailUrl = item.thumbnailUrl,
                            streamUrl = viewModel.absoluteMediaUrl(item.streamUrl),
                        )
                    }
                    buildRows(videoItems)
                }
            }
        }
    }

    private fun buildRows(items: List<VideoItem>) {
        rowsAdapter.clear()
        if (items.isEmpty()) return

        val listRowAdapter = ArrayObjectAdapter(VideoCardPresenter())
        items.forEach { listRowAdapter.add(it) }
        
        val header = HeaderItem(0, "Library")
        rowsAdapter.add(ListRow(header, listRowAdapter))
    }

    fun openServerDialog() {
        ServerConfigDialogFragment().show(childFragmentManager, "server_config")
    }

    fun submitServerUrl(url: String) {
        viewModel.saveServerUrl(url)
    }

    private fun dp(context: android.content.Context, dp: Int): Int {
        return (dp * context.resources.displayMetrics.density).toInt()
    }
}

private class CustomHeaderPresenter : RowHeaderPresenter() {
    override fun onBindViewHolder(viewHolder: Presenter.ViewHolder?, item: Any?) {
        super.onBindViewHolder(viewHolder, item)
        val headerView = (viewHolder?.view as? RowHeaderView) ?: return
        headerView.setTextColor(ContextCompat.getColor(headerView.context, R.color.tv_accent))
        headerView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
    }
}

private class VideoCardPresenter : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val cardView = ImageCardView(parent.context).apply {
            isFocusable = true
            isFocusableInTouchMode = true
            setMainImageDimensions(560, 315)
            setInfoAreaBackgroundColor(ContextCompat.getColor(context, R.color.tv_white))
            
            findViewById<TextView>(androidx.leanback.R.id.title_text)?.apply {
                setTextColor(ContextCompat.getColor(context, R.color.tv_text))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setTypeface(null, android.graphics.Typeface.BOLD)
            }
            findViewById<TextView>(androidx.leanback.R.id.content_text)?.apply {
                setTextColor(ContextCompat.getColor(context, R.color.tv_muted))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            }
        }
        return ViewHolder(cardView)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any?) {
        val video = item as VideoItem
        val cardView = viewHolder.view as ImageCardView
        cardView.titleText = video.title
        cardView.contentText = video.subtitle
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder?) {
        val cardView = viewHolder?.view as? ImageCardView
        cardView?.mainImage = null
    }
}
