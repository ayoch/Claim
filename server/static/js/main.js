// Check if admin key is set
if (localStorage.getItem('adminKey')) {
    document.getElementById('admin-link').style.display = 'block';
}

// Load recent blog posts
async function loadRecentPosts() {
    try {
        const response = await fetch('/api/blog/posts?limit=3');
        const posts = await response.json();

        const container = document.getElementById('recent-posts-list');

        if (posts.length === 0) {
            container.innerHTML = '<p class="loading">No posts yet.</p>';
            return;
        }

        container.innerHTML = posts.map(post => `
            <div class="post-card">
                <h4><a href="/post.html?slug=${post.slug}" style="color: inherit; text-decoration: none;">${post.title}</a></h4>
                <p class="post-excerpt">${post.excerpt}</p>
                <p class="post-meta">${new Date(post.published_at).toLocaleDateString('en-US', {
                    year: 'numeric',
                    month: 'long',
                    day: 'numeric'
                })}</p>
            </div>
        `).join('');
    } catch (error) {
        console.error('Failed to load posts:', error);
        document.getElementById('recent-posts-list').innerHTML =
            '<p class="loading">Failed to load posts.</p>';
    }
}

// Load posts on page load
loadRecentPosts();
