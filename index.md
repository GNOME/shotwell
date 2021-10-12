---
layout: default
---
![Pixels](assets/splash.png){:.full.pixels}


[OS Component Template](https://github.com/jimmac/os-component-website) is a project that aims to greatly simplify creating a  website for your project. It aims to let you write simple markdown pages and deploy the simple jekyll project to [gitlab](https://gitlab.org) or [github](https://github.com).
 
Edit a bit of metadata and tweak some of the included graphics and have a site up in minutes!


- Proper favicon for modern browsers and Apple device icons
- Twitter, Facebook and other social media meta cards for easy sharing. Try [Share Preview](https://flathub.org/apps/details/com.rafaelmardojai.SharePreview) to test.
- Local copy of the amazing [Inter font](https://rsms.me/inter/). No slowdowns pulling from external hosting.
- Mobile friendly, dark variant included.


## Setup

The process of setting up the site locally consists of:

- Install ruby [gem bundler](https://bundler.io/). On [Fedora](https://getfedora.org/)/in the [Toolbx](https://containertoolbx.org) you do:

```
toolbox enter
sudo dnf install rubygem-bundler
cd os-component-website
bundle install
```

- Edit the [Jekyll](https://jekyllrb.com/) config file --`_config.yml`.
- Replace or edit all the graphics. I recommend using [Inkscape](https://inkscape.org). If you want to shave off some kB out of the SVGs, use [svgo](https://github.com/svg/svgo).

- Test the site locally:
```
bundle exec jekyll s
```

- `git commit` your changes and push to your remote repo for automatic deployment. There is an included `.gitlab-ci.yml` that should be easy to adjust to your gitlab hosting situation. For github pages situation, [see these instructions](https://pages.github.com/). 

Alternatively you can be wild and edit the site directly on github using the remote VSCode editor by pressing `.` after cloning the repo. Right in the browser. It's insane.

Written with love using [Apostrophe](https://flathub.org/apps/details/org.gnome.gitlab.somas.Apostrophe).