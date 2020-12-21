import React from "react";
import {Link} from "gatsby";
import Img from "gatsby-image";

function Singlerelease({release}) {
  return (
    <div>
      <Link to={`/release/${release.slug.current}`}>
        <h2>
          <span className="mark">{release.name}</span>
        </h2>
        <p>{release.artists.map((info) => info.name)}</p>
        <Img fluid={release.image.asset.fluid} alt={release.name} />
      </Link>
    </div>
  );
}

export default function releaseList({releases}) {
  return (
    <div>
      {releases.map((release) => (
        <Singlerelease key={release.id} release={release} />
      ))}
    </div>
  );
}
