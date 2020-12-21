import {v4 as uuidv4} from "uuid";
import {graphql} from "gatsby";
// function mixData({data}) {
//   console.log(data)
//   return data.map((mix) => {
//     [
//       {
//         name: mix.name,
//         cover:
//           "https://chillhop.com/wp-content/uploads/2020/09/0255e8b8c74c90d4a27c594b3452b2daafae608d-1024x1024.jpg",
//         artist: "Aso, Middle School, Aviino",
//         audio: "https://mp3.chillhop.com/serve.php/?mp3=10075",
//         color: ["#205950", "#2ab3bf"],
//         id: uuidv4(),
//         active: true,
//       },
//     ];
//   });
// }


//export default mixData;

export const query = graphql`
  query MixData {
    content: allSanityInterview {
      nodes {
        active
        id
        cat
        artist
        name
        color
        audio {
          asset {
            url
          }
        }
        image {
          asset {
            fixed(width: 200, height: 200) {
              ...GatsbySanityImageFixed
            }
            fluid(maxWidth: 200) {
              ...GatsbySanityImageFluid
            }
          }
        }
      }
    }
  }
`;
