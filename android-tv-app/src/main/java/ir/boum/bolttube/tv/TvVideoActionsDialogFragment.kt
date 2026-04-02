package ir.boum.bolttube.tv

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.activityViewModels

class TvVideoActionsDialogFragment : DialogFragment() {

    private val viewModel: TvViewModel by activityViewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setStyle(STYLE_NO_TITLE, android.R.style.Theme_DeviceDefault_Light_Dialog_NoActionBar)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        return inflater.inflate(R.layout.dialog_tv_video_actions, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val titleView = view.findViewById<TextView>(R.id.actionDialogTitle)
        val offloadButton = view.findViewById<View>(R.id.actionOffloadButton)
        val deleteButton = view.findViewById<View>(R.id.actionDeleteButton)
        val cancelButton = view.findViewById<View>(R.id.actionCancelButton)

        val mediaId = requireArguments().getString(ARG_MEDIA_ID).orEmpty()
        val title = requireArguments().getString(ARG_TITLE).orEmpty()
        val isOffloaded = requireArguments().getBoolean(ARG_IS_OFFLOADED)

        titleView.text = title
        offloadButton.visibility = if (isOffloaded) View.GONE else View.VISIBLE

        listOf(offloadButton, deleteButton, cancelButton).forEach { button ->
            button.setOnFocusChangeListener { v, hasFocus ->
                v.animate()
                    .scaleX(if (hasFocus) 1.04f else 1f)
                    .scaleY(if (hasFocus) 1.04f else 1f)
                    .setDuration(150)
                    .start()
            }
        }

        offloadButton.setOnClickListener {
            dismiss()
            viewModel.offloadItem(mediaId)
        }
        deleteButton.setOnClickListener {
            dismiss()
            viewModel.deleteItem(mediaId)
        }
        cancelButton.setOnClickListener {
            dismiss()
        }

        val initialFocusId = if (isOffloaded) R.id.actionDeleteButton else R.id.actionOffloadButton
        val initialFocusView = view.findViewById<View>(initialFocusId)
        initialFocusView?.post {
            initialFocusView.requestFocus()
        }
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        dialog?.window?.setLayout(dp(420), ViewGroup.LayoutParams.WRAP_CONTENT)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val ARG_MEDIA_ID = "media_id"
        private const val ARG_TITLE = "title"
        private const val ARG_IS_OFFLOADED = "is_offloaded"

        fun newInstance(mediaId: String, title: String, isOffloaded: Boolean): TvVideoActionsDialogFragment {
            return TvVideoActionsDialogFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_MEDIA_ID, mediaId)
                    putString(ARG_TITLE, title)
                    putBoolean(ARG_IS_OFFLOADED, isOffloaded)
                }
            }
        }
    }
}
