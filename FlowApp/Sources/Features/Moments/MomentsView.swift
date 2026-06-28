import SwiftUI
import PhotosUI

/// 朋友圈/动态流（发现页第三栏）。发帖 / 点赞 / 评论。
struct MomentsView: View {
    @EnvironmentObject var loc: Localization
    @State private var posts: [MomentPost] = []
    @State private var loaded = false
    @State private var showCompose = false
    @State private var commentsFor: MomentPost?

    var body: some View {
        ScrollView {
            Button { showCompose = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text(loc.t("moments.post")).font(FlowTheme.caption(14).weight(.medium))
                }
                .foregroundStyle(FlowTheme.teal).frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.teal.opacity(0.1)))
                .sketchBorder(14, width: 1.2, seed: 90)
            }
            .padding(.horizontal, 16).padding(.top, 6)

            if loaded && posts.isEmpty {
                Text(loc.t("moments.empty")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray).padding(.top, 40)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(Array(posts.enumerated()), id: \.element.id) { idx, p in
                        postCard(p, seed: UInt64(idx + 400))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await reload() }
        .sheet(isPresented: $showCompose) { ComposeMomentView { Task { await reload() } } }
        .sheet(item: $commentsFor) { p in CommentsSheet(post: p) { Task { await reload() } } }
    }

    private func postCard(_ p: MomentPost, seed: UInt64) -> some View {
        Card(seed: seed) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    Avatar(initials: p.author_initials, tint: FlowTheme.tint(["teal","sage","tealDark","ink","gray"][p.author_id % 5]), size: 40, seed: seed, imageURL: p.author_avatar_url)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.author_name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                        Text(p.shortTime).font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
                    }
                    Spacer()
                }
                if !p.content.isEmpty {
                    Text(p.content).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = p.image_url, let u = URL(string: url) {
                    AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { FlowTheme.beige }
                        .frame(height: 160).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack(spacing: 20) {
                    Button { like(p) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: p.liked ? "heart.fill" : "heart").foregroundStyle(p.liked ? FlowTheme.teal : FlowTheme.gray)
                            Text("\(p.like_count)").font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                        }
                    }
                    Button { commentsFor = p } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bubble.right").foregroundStyle(FlowTheme.gray)
                            Text("\(p.comment_count)").font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(16)
        }
    }

    private func reload() async {
        let ps = (try? await APIClient.shared.momentsFeed()) ?? []
        await MainActor.run { posts = ps; loaded = true }
    }

    private func like(_ p: MomentPost) {
        Task {
            if let r = try? await APIClient.shared.toggleLike(postId: p.id), let i = posts.firstIndex(where: { $0.id == p.id }) {
                await MainActor.run { posts[i].liked = r.liked; posts[i].like_count = r.like_count }
            }
        }
    }
}

struct ComposeMomentView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    var onPosted: () -> Void = {}
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageURL: String?
    @State private var uploading = false
    @State private var posting = false
    @State private var polishing = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { dismiss() } label: { Text(loc.t("common.cancel")).foregroundStyle(FlowTheme.gray) }
                Spacer()
                Text(loc.t("moments.post")).font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { post() } label: { Text(loc.t("moments.send")).foregroundStyle(FlowTheme.teal).fontWeight(.semibold) }
                    .disabled(posting || (text.trimmingCharacters(in: .whitespaces).isEmpty && imageURL == nil))
            }
            TextEditor(text: $text)
                .font(FlowTheme.body(16)).frame(maxHeight: .infinity)
                .padding(10).background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.field)).sketchBorder(14, width: 1.3, seed: 91)

            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                        Text(uploading ? loc.t("moments.uploading") : loc.t("moments.addPhoto")).font(FlowTheme.caption(13))
                    }
                    .foregroundStyle(FlowTheme.teal)
                }
                Button { polish() } label: {
                    HStack(spacing: 6) {
                        if polishing { ProgressView().scaleEffect(0.7) }
                        else { Image(systemName: "wand.and.stars") }
                        Text(loc.t("moments.polish")).font(FlowTheme.caption(13))
                    }
                    .foregroundStyle(FlowTheme.teal)
                }
                .disabled(polishing || text.trimmingCharacters(in: .whitespaces).isEmpty)
                if let url = imageURL, let u = URL(string: url) {
                    Spacer()
                    AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { FlowTheme.beige }
                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                    Button { imageURL = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(FlowTheme.gray) }
                }
                Spacer()
            }
        }
        .padding(20).background(PaperBackground())
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            uploading = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let url = try? await APIClient.shared.uploadImage(data) {
                    await MainActor.run { imageURL = url }
                }
                await MainActor.run { uploading = false; photoItem = nil }
            }
        }
    }

    private func polish() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !polishing else { return }
        polishing = true
        Task {
            let result = try? await APIClient.shared.rewrite(text: t, tone: "自然")
            await MainActor.run {
                if let r = result, !r.isEmpty { text = r }
                polishing = false
            }
        }
    }

    private func post() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || imageURL != nil, !posting else { return }
        posting = true
        Task {
            _ = try? await APIClient.shared.createPost(content: t, imageURL: imageURL)
            onPosted()
            await MainActor.run { posting = false; dismiss() }
        }
    }
}

struct CommentsSheet: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let post: MomentPost
    var onChanged: () -> Void = {}
    @State private var comments: [MomentComment] = []
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("moments.comments")).font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }.padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(comments) { cm in
                        HStack(alignment: .top, spacing: 10) {
                            Avatar(initials: cm.initials, tint: FlowTheme.teal, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cm.user_name).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                                Text(cm.content).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                            }
                            Spacer()
                        }
                    }
                }.padding(.horizontal, 20)
            }
            HStack(spacing: 10) {
                TextField(loc.t("moments.commentHint"), text: $draft)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20).fill(FlowTheme.field)).sketchBorder(20, width: 1.3, seed: 92)
                Button { add() } label: { PillButton(title: loc.t("moments.send"), radius: 20, seed: 93) }
            }
            .padding(16)
        }
        .background(PaperBackground())
        .task { comments = (try? await APIClient.shared.listComments(postId: post.id)) ?? [] }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        Task {
            if let cm = try? await APIClient.shared.addComment(postId: post.id, content: t) {
                await MainActor.run { comments.append(cm) }
                onChanged()
            }
        }
    }
}
