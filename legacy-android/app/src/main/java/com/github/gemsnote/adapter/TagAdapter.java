package com.github.gemsnote.adapter;


import androidx.recyclerview.widget.RecyclerView;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import com.github.gemsnote.R;
import com.github.gemsnote.model.Account;
import com.github.gemsnote.model.Tag;

import java.util.List;

import butterknife.BindView;
import butterknife.ButterKnife;

public class TagAdapter extends RecyclerView.Adapter<TagAdapter.TagHolder> {

    private List<Tag> mData;
    private TagAdapterListener mListener;

    public void setListener(TagAdapterListener listener) {
        mListener = listener;
    }

    public void refresh() {
        mData = Tag.getAllTags(Account.getCurrent().getUserId());
        notifyDataSetChanged();
    }

    @Override
    public TagHolder onCreateViewHolder(ViewGroup parent, int viewType) {
        View view;
        view = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_tag, parent, false);
        return new TagHolder(view);
    }

    @Override
    public void onBindViewHolder(TagHolder holder, int position) {
        final Tag tag = mData.get(position);
        holder.titleTv.setText(tag.getText());
        holder.itemView.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (mListener != null) {
                    mListener.onClickedTag(tag);
                }
            }
        });
        holder.itemView.setOnLongClickListener(new View.OnLongClickListener() {
            @Override
            public boolean onLongClick(View v) {
                if (mListener != null) {
                    mListener.onLongClickedTag(tag);
                    return true;
                }
                return false;
            }
        });
    }

    @Override
    public int getItemCount() {
        return mData == null ? 0 : mData.size();
    }

    public interface TagAdapterListener {
        void onClickedTag(Tag tag);

        void onLongClickedTag(Tag tag);
    }

    static class TagHolder extends RecyclerView.ViewHolder {
        View itemView;
        @BindView(R.id.tv_title)
        TextView titleTv;

        public TagHolder(View itemView) {
            super(itemView);
            this.itemView = itemView;
            ButterKnife.bind(this, itemView);
        }
    }
}