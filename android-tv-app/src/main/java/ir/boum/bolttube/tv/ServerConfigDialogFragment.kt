package ir.boum.bolttube.tv

import android.app.Dialog
import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import android.widget.EditText
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.DialogFragment

class ServerConfigDialogFragment : DialogFragment() {

    interface Listener {
        fun onServerSubmitted(url: String)
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val context = requireContext()
        val input = EditText(context).apply {
            setText(requireArguments().getString(ARG_CURRENT_URL).orEmpty())
            hint = context.getString(R.string.server_dialog_hint)
            setSelection(text.length)
        }

        return AlertDialog.Builder(context, R.style.Theme_BoltTubeTV_Dialog)
            .setTitle(R.string.server_dialog_title)
            .setView(input)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                (activity as? Listener)?.onServerSubmitted(input.text.toString())
            }
            .setNegativeButton(android.R.string.cancel, null)
            .create()
            .also { dialog ->
                dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
            }
    }

    companion object {
        private const val ARG_CURRENT_URL = "current_url"

        fun newInstance(currentUrl: String): ServerConfigDialogFragment {
            return ServerConfigDialogFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_CURRENT_URL, currentUrl)
                }
            }
        }
    }
}
